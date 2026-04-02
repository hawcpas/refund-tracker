import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../widgets/page_scaffold.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _db = FirebaseFirestore.instance;

  bool _busy = false;

  int get _selectedCount => _selectedUids.length;

  final Set<String> _selectedUids = <String>{};
  int _clearSelectionToken = 0; // tells _UsersPane to clear selection

  bool _roleLoading = true;
  String _role = '';
  String? _roleError;

  final _userSearchCtrl = TextEditingController();
  String get _userQuery => _userSearchCtrl.text.trim().toLowerCase();

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  void _clearSelection() {
    if (_selectedUids.isEmpty) return;
    setState(() {
      _selectedUids.clear();
      _clearSelectionToken++; // tells _UsersPane to clear its local selection too
    });
  }

  @override
  void initState() {
    super.initState();
    _loadMyRole();
    _userSearchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _userSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyRole() async {
    setState(() {
      _roleLoading = true;
      _roleError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _role = '';
          _roleLoading = false;
        });
        return;
      }

      final doc = await _db.collection('users').doc(user.uid).get();

      final role = (doc.data()?['role'] ?? '').toString().toLowerCase().trim();

      if (!mounted) return;
      setState(() {
        _role = role;
        _roleLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _roleError = e.toString();
        _roleLoading = false;
        _role = '';
      });
    }
  }

  // -------------------------
  // Cloud Function helpers
  // -------------------------
  HttpsCallable _callable(String name) {
    return FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable(name);
  }

  Future<void> _bulkRemoveSelectedUsers() async {
    if (_busy || _selectedUids.isEmpty) return;

    // Confirm once
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove selected users'),
        content: Text(
          'You are about to permanently remove ${_selectedUids.length} user(s).\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);

    int deleted = 0;
    int skipped = 0;

    try {
      // Safety: don't delete yourself
      final myUid = _myUid;

      // Safety: ensure at least 1 admin remains
      final adminsSnap = await _db
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
      final adminCount = adminsSnap.size;

      // Count selected admins
      int selectedAdminCount = 0;
      for (final uid in _selectedUids) {
        final u = await _db.collection('users').doc(uid).get();
        final role = ((u.data()?['role']) ?? '')
            .toString()
            .toLowerCase()
            .trim();
        if (role == 'admin') selectedAdminCount++;
      }
      if (adminCount - selectedAdminCount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('At least one admin must remain.')),
        );
        return;
      }

      final callable = _callable('deleteUser');

      // Execute deletes
      for (final uid in _selectedUids.toList()) {
        if (myUid != null && uid == myUid) {
          skipped++;
          continue;
        }

        final snap = await _db.collection('users').doc(uid).get();
        if (!snap.exists) {
          skipped++;
          continue;
        }

        final data = snap.data() ?? {};
        final email = (data['email'] ?? '').toString().trim();
        final role = (data['role'] ?? '').toString().toLowerCase().trim();

        // Extra safety: if deleting an admin, re-check remaining admins
        if (role == 'admin') {
          final currentAdmins = await _db
              .collection('users')
              .where('role', isEqualTo: 'admin')
              .get();
          if (currentAdmins.size <= 1) {
            skipped++;
            continue;
          }
        }

        try {
          await callable.call({'uid': uid, 'email': email});
          deleted++;
        } catch (_) {
          skipped++;
        }
      }

      // Clear selection everywhere (parent + child)
      setState(() {
        _selectedUids.clear();
        _clearSelectionToken++; // tells UsersPane to clear
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted > 0
                ? 'Removed $deleted user(s)${skipped > 0 ? ' • Skipped $skipped' : ''}.'
                : 'No users were removed${skipped > 0 ? ' • Skipped $skipped' : ''}.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateUser({
    required String uid,
    required String email,
    required String role,
    required String status,
    required String reason,
    required String firstName,
    required String lastName,
    Map<String, dynamic>? communications,
  }) async {
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'uid': uid,
        'email': email,
        'role': role,
        'status': status,
        'reason': reason,
        'firstName': firstName,
        'lastName': lastName,
      };

      if (communications != null) {
        payload['communications'] = communications;
      }

      await _callable('updateUser').call(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User updated')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${e.code} ${e.message ?? ''}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setUserDisabled({
    required String uid,
    required bool disabled,
    required String reason,
  }) async {
    setState(() => _busy = true);
    try {
      await _callable(
        'setUserDisabled',
      ).call({'uid': uid, 'disabled': disabled, 'reason': reason});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(disabled ? 'User deactivated' : 'User reactivated'),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: ${e.code} ${e.message ?? ''}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset({
    required String uid,
    required String email,
  }) async {
    setState(() => _busy = true);
    try {
      await _callable('sendPasswordReset').call({'uid': uid, 'email': email});

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Password reset sent to $email')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: ${e.code} ${e.message ?? ''}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendInvite({required String uid}) async {
    setState(() => _busy = true);
    try {
      final res = await _callable('resendInvite').call({'uid': uid});
      final data = Map<String, dynamic>.from(res.data as Map);
      final email = (data['email'] ?? '').toString();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite resent to $email')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resend failed: ${e.code} ${e.message ?? ''}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------
  // UI dialogs
  // -------------------------
  Future<String?> _promptReason({
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: hint,
            prefixIcon: const Icon(Icons.note_alt_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (ok != true) return null;
    return ctrl.text.trim();
  }

  Future<void> _showEditUserDialog({
    required String uid,
    required String currentEmail,
    required String currentRole,
    required String currentStatus,
    required String currentFirstName,
    required String currentLastName,
    required String currentDisplayName,
    Map<String, dynamic>? currentCommunications,
  }) async {
    final firstNameCtrl = TextEditingController(text: currentFirstName);
    final lastNameCtrl = TextEditingController(text: currentLastName);
    final emailCtrl = TextEditingController(text: currentEmail);

    String role = (currentRole.isEmpty ? 'associate' : currentRole)
        .toLowerCase()
        .trim();
    String status = (currentStatus.isEmpty ? 'active' : currentStatus)
        .toLowerCase()
        .trim();

    final reasonCtrl = TextEditingController();

    final comms = Map<String, dynamic>.from(currentCommunications ?? {});
    final wildixCtrl = TextEditingController(
      text: (comms['wildixExtension'] ?? '').toString(),
    );
    final clearflyCtrl = TextEditingController(
      text: (comms['clearflySmsNumber'] ?? '').toString(),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit user'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'First name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Last name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'associate',
                    child: Text('Associate'),
                  ),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => role = (v ?? 'associate'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.verified_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'invited', child: Text('Invited')),
                  DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
                ],
                onChanged: (v) => status = (v ?? 'active'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason (audit note)',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Communications',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: wildixCtrl,
                decoration: const InputDecoration(
                  labelText: 'Wildix Extension',
                  prefixIcon: Icon(Icons.phone_in_talk_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: clearflyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Clearfly SMS / eFax Number',
                  prefixIcon: Icon(Icons.sms_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final email = emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid email')));
      return;
    }

    status = status == 'inactive' ? 'disabled' : status;

    await _updateUser(
      uid: uid,
      email: email,
      role: role,
      status: status,
      reason: reasonCtrl.text.trim(),
      firstName: firstNameCtrl.text.trim(),
      lastName: lastNameCtrl.text.trim(),
      communications: {
        'wildixExtension': wildixCtrl.text.trim(),
        'clearflySmsNumber': clearflyCtrl.text.trim(),
      },
    );
  }

  Future<void> _inviteUser({
    required String email,
    required String role,
    required String firstName,
    required String lastName,
  }) async {
    setState(() => _busy = true);

    try {
      final res = await _callable('inviteUser').call({
        'email': email,
        'role': role,
        'firstName': firstName,
        'lastName': lastName,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final invitedEmail = (data['email'] ?? email).toString();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('User created for $invitedEmail')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      final msg = [
        'Invite failed: ${e.code}',
        if (e.message != null) 'Message: ${e.message}',
        if (e.details != null) 'Details: ${e.details}',
      ].join('\n');

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      debugPrint(msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteUser({
    required String uid,
    required String email,
    required String label,
    required String targetRole,
    required bool isLastAdmin,
  }) async {
    if (_myUid != null && uid == _myUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot delete yourself.')),
      );
      return;
    }

    if (targetRole.toLowerCase() == 'admin' && isLastAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot delete the last admin.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete user'),
        content: Text(
          'Are you sure you want to delete $label?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);

    try {
      await _callable('deleteUser').call({'uid': uid, 'email': email});

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted $label')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      final msg = [
        'Delete failed: ${e.code}',
        if (e.message != null) 'Message: ${e.message}',
        if (e.details != null) 'Details: ${e.details}',
      ].join('\n');

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      debugPrint(msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showInviteDialog() async {
    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String role = 'associate';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite user'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameCtrl,
              decoration: const InputDecoration(
                labelText: 'First name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Last name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(
                labelText: 'Role',
                prefixIcon: Icon(Icons.admin_panel_settings_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'associate', child: Text('Associate')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (v) => role = v ?? 'associate',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    final firstName = firstNameCtrl.text.trim();
                    final lastName = lastNameCtrl.text.trim();
                    final email = emailCtrl.text.trim().toLowerCase();

                    if (firstName.isEmpty || lastName.isEmpty) return;
                    if (!email.contains('@')) return;

                    Navigator.pop(ctx);
                    await _inviteUser(
                      email: email,
                      role: role,
                      firstName: firstName,
                      lastName: lastName,
                    );
                  },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_roleLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_roleError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 34),
              const SizedBox(height: 10),
              const Text('Could not load your admin role.'),
              const SizedBox(height: 8),
              Text(
                _roleError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: _loadMyRole, child: const Text('Retry')),
            ],
          ),
        ),
      );
    } else if (_role != 'admin') {
      body = const Center(child: Text('Admin access required.'));
    } else {
      body = PageScaffold(
        title: 'Admin Console',
        subtitle: 'Manage firm users, roles, and account access.',
        wrapInCard: false,
        scrollable: false, // ✅ CRITICAL FIX
        // ✅ All admin actions now live in the command bar
        commandBar: FluentCommandBar(
          actions: [
            FluentCommandAction(
              icon: Icons.person_add_alt_1,
              label: 'Invite user',
              onPressed: _busy ? null : _showInviteDialog,
            ),
            FluentCommandAction(
              icon: Icons.delete_outline,
              label: _selectedCount == 0
                  ? 'Remove users'
                  : 'Remove users ($_selectedCount)',
              onPressed: (_busy || _selectedCount == 0)
                  ? null
                  : _bulkRemoveSelectedUsers,
            ),
            FluentCommandAction(
              icon: Icons.refresh,
              label: 'Refresh',
              onPressed: _busy ? null : _loadMyRole,
            ),
          ],
        ),

        child: Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: _UsersPane(
                    db: _db,
                    myUid: _myUid,
                    busy: _busy,
                    query: _userQuery,
                    searchCtrl: _userSearchCtrl,
                    onDeleteUser: _deleteUser,
                    onEditUser: _showEditUserDialog,
                    onResendInvite: _resendInvite,
                    onSendPasswordReset: _sendPasswordReset,
                    onSetDisabled: _setUserDisabled,
                    promptReason: _promptReason,
                    clearSelectionToken: _clearSelectionToken,
                    onSelectionChanged: (ids) {
                      setState(() {
                        _selectedUids
                          ..clear()
                          ..addAll(ids);
                      });
                    },
                  ),
                ),
              ),

              if (_busy)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      );
    }

    return body;
  }
}

// -------------------- Your helper widgets stay unchanged below --------------------

class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final String selected;
  final ValueChanged<String> onSelected;

  const _SearchHeader({
    required this.controller,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget chip(String label, String value) {
      final bool active = selected == value;
      return ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onSelected(value),
        selectedColor: theme.colorScheme.primary.withOpacity(0.14),
        backgroundColor: theme.colorScheme.surface.withOpacity(0.4),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          color: active
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final chips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('All', 'all'),
        const SizedBox(width: 6),
        chip('Active', 'active'),
        const SizedBox(width: 6),
        chip('Invited', 'invited'),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.35)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, c) {
          final isNarrow = c.maxWidth < 520;

          final searchField = TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Search users by name or email…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: chips,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              chips,
            ],
          );
        },
      ),
    );
  }
}

// NOTE: Keep your existing _UsersPane, _MetaChip, _StatusPill, _ErrorBox, _EmptyBox
// exactly as they already are below this point.
// (Your pasted code continues — do NOT change those.)

class _UsersPane extends StatefulWidget {
  final FirebaseFirestore db;
  final String? myUid;
  final bool busy;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<Set<String>> onSelectionChanged;
  final int clearSelectionToken; // NEW

  final Future<void> Function({
    required String uid,
    required String email,
    required String label,
    required String targetRole,
    required bool isLastAdmin,
  })
  onDeleteUser;

  final Future<void> Function({
    required String uid,
    required String currentEmail,
    required String currentRole,
    required String currentStatus,

    // ✅ NEW
    required String currentFirstName,
    required String currentLastName,
    required String currentDisplayName,

    Map<String, dynamic>? currentCommunications,
  })
  onEditUser;

  final Future<void> Function({required String uid}) onResendInvite;

  final Future<void> Function({required String uid, required String email})
  onSendPasswordReset;

  final Future<void> Function({
    required String uid,
    required bool disabled,
    required String reason,
  })
  onSetDisabled;

  final Future<String?> Function({required String title, required String hint})
  promptReason;

  const _UsersPane({
    required this.db,
    required this.myUid,
    required this.busy,
    required this.query,
    required this.searchCtrl,
    required this.onDeleteUser,
    required this.onEditUser,
    required this.onResendInvite,
    required this.onSendPasswordReset,
    required this.onSetDisabled,
    required this.promptReason,
    required this.onSelectionChanged,
    required this.clearSelectionToken, // ✅ NEW
  });

  @override
  State<_UsersPane> createState() => _UsersPaneState();
}

class _UsersPaneState extends State<_UsersPane> {
  final Set<String> _selected = <String>{};
  String _statusFilter = 'all'; // all | active | invited

  String _formatDateOnly(BuildContext context, DateTime dt) {
    return MaterialLocalizations.of(context).formatShortDate(dt);
  }

  void _notifySelection() {
    widget.onSelectionChanged(Set<String>.from(_selected));
  }

  int _lastClearToken = 0;

  @override
  void didUpdateWidget(covariant _UsersPane oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.clearSelectionToken != _lastClearToken) {
      _lastClearToken = widget.clearSelectionToken;
      if (_selected.isNotEmpty) {
        setState(() => _selected.clear());
        _notifySelection();
      }
    }
  }

  Widget _actionsMenu({
    required bool isMe,
    required bool isInvited,
    required bool isDisabled,
    required bool isLastAdmin,
    required String uid,
    required String email,
    required String role,
    required String status,
    required String titleName,
    required String firstName,
    required String lastName,
    required String displayName,
    required Map<String, dynamic> communications,
  }) {
    if (isMe) return const SizedBox(width: 40, height: 36);

    return SizedBox(
      width: 40,
      height: 36,
      child: Align(
        alignment: Alignment.topRight,
        child: PopupMenuButton<String>(
          tooltip: 'Actions',
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (value) async {
            if (widget.busy) return;

            if (value == 'edit') {
              await widget.onEditUser(
                uid: uid,
                currentEmail: email,
                currentRole: role,
                currentStatus: status,

                // ✅ NEW
                currentFirstName: firstName,
                currentLastName: lastName,
                currentDisplayName: displayName,

                currentCommunications: communications,
              );
            } else if (value == 'resendInvite') {
              await widget.onResendInvite(uid: uid);
            } else if (value == 'resetPassword') {
              if (!email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User has no valid email')),
                );
                return;
              }
              await widget.onSendPasswordReset(uid: uid, email: email);
            } else if (value == 'deactivate') {
              if (isLastAdmin) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You cannot deactivate the last admin.'),
                  ),
                );
                return;
              }

              final reason = await widget.promptReason(
                title: 'Deactivate user',
                hint: 'Reason (audit note)',
              );
              if (reason == null) return;

              await widget.onSetDisabled(
                uid: uid,
                disabled: true,
                reason: reason,
              );
            } else if (value == 'reactivate') {
              final reason = await widget.promptReason(
                title: 'Reactivate user',
                hint: 'Reason (audit note)',
              );
              if (reason == null) return;

              await widget.onSetDisabled(
                uid: uid,
                disabled: false,
                reason: reason,
              );
            } else if (value == 'delete') {
              await widget.onDeleteUser(
                uid: uid,
                email: email,
                label: titleName,
                targetRole: role,
                isLastAdmin: isLastAdmin,
              );
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit user')),
            const PopupMenuItem(
              value: 'resetPassword',
              child: Text('Send password reset'),
            ),
            if (isInvited)
              const PopupMenuItem(
                value: 'resendInvite',
                child: Text('Resend invite'),
              ),
            const PopupMenuDivider(),
            if (isDisabled)
              const PopupMenuItem(
                value: 'reactivate',
                child: Text('Reactivate'),
              )
            else
              PopupMenuItem(
                value: 'deactivate',
                enabled: !isLastAdmin,
                child: Text(
                  isLastAdmin ? 'Deactivate (not allowed)' : 'Deactivate',
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              enabled: !isLastAdmin,
              child: Text(isLastAdmin ? 'Delete (not allowed)' : 'Delete user'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max, // ✅ IMPORTANT: give children real height
      children: [
        _SearchHeader(
          controller: widget.searchCtrl,
          selected: _statusFilter,
          onSelected: (v) => setState(() => _statusFilter = v),
        ),
        const Divider(height: 1),

        // ✅ IMPORTANT: Expanded guarantees finite height for _UsersTable's Expanded
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: widget.db.collection('users').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return _ErrorBox(error: snap.error.toString());
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs.toList();

              final adminCount = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['role'] ?? '').toString().toLowerCase() == 'admin';
              }).length;

              docs.sort((a, b) {
                final ae = ((a.data() as Map)['email'] ?? a.id)
                    .toString()
                    .toLowerCase();
                final be = ((b.data() as Map)['email'] ?? b.id)
                    .toString()
                    .toLowerCase();
                return ae.compareTo(be);
              });

              final filtered = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final email = (data['email'] ?? '').toString().toLowerCase();
                final fn = (data['firstName'] ?? '').toString().toLowerCase();
                final ln = (data['lastName'] ?? '').toString().toLowerCase();
                final dn = (data['displayName'] ?? '').toString().toLowerCase();
                final status = (data['status'] ?? '').toString().toLowerCase();

                final matchesSearch =
                    widget.query.isEmpty ||
                    ('$email $fn $ln $dn').contains(widget.query);

                final matchesStatus =
                    _statusFilter == 'all' || status == _statusFilter;

                return matchesSearch && matchesStatus;
              }).toList();

              if (filtered.isEmpty) {
                return const _EmptyBox(
                  icon: Icons.group_outlined,
                  title: 'No users found',
                  subtitle: 'Try adjusting your search or filter.',
                );
              }

              // ✅ STEP 2 — Decide layout based on screen width
              final isPhone = MediaQuery.of(context).size.width < 520;

              if (isPhone) {
                // ✅ MOBILE: keep existing card layout
                return ListView.separated(
                  shrinkWrap: true,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(10),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 16,
                    thickness: 1,
                    color: Theme.of(context).dividerColor.withOpacity(0.35),
                    indent: 12,
                    endIndent: 12,
                  ),
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final data = d.data() as Map<String, dynamic>;

                    final uid = d.id;
                    final email = (data['email'] ?? '').toString();
                    final firstName = (data['firstName'] ?? '').toString();
                    final lastName = (data['lastName'] ?? '').toString();
                    final displayName = (data['displayName'] ?? '').toString();
                    final role = (data['role'] ?? 'associate').toString();
                    final status = (data['status'] ?? '').toString();

                    final communications = Map<String, dynamic>.from(
                      data['communications'] ?? {},
                    );
                    final wildixExt = (communications['wildixExtension'] ?? '')
                        .toString()
                        .trim();
                    final clearflyNum =
                        (communications['clearflySmsNumber'] ?? '')
                            .toString()
                            .trim();

                    final statusLower = status.toLowerCase().trim();
                    final normalizedStatus = statusLower == 'inactive'
                        ? 'disabled'
                        : statusLower;

                    final isInvited = normalizedStatus == 'invited';
                    final isDisabled =
                        (data['disabled'] == true) ||
                        normalizedStatus == 'disabled';

                    DateTime? invitedDt;
                    final invitedAt = data['invitedAt'];
                    if (invitedAt is Timestamp) invitedDt = invitedAt.toDate();

                    DateTime? lastSignInDt;
                    final lastSignInAt = data['lastSignInAt'];
                    if (lastSignInAt is Timestamp)
                      lastSignInDt = lastSignInAt.toDate();

                    final isMe = widget.myUid != null && uid == widget.myUid;
                    final theme = Theme.of(context);

                    final nameLabel = displayName.isNotEmpty
                        ? displayName
                        : ('$firstName $lastName').trim();
                    final titleName = nameLabel.isNotEmpty
                        ? nameLabel
                        : (email.isNotEmpty ? email : uid);
                    final emailLine = email.isNotEmpty ? email : uid;

                    final isLastAdmin =
                        role.toLowerCase() == 'admin' && adminCount <= 1;

                    final metaLine = isInvited
                        ? (invitedDt == null
                              ? 'Invited • —'
                              : 'Invited • ${_formatDateOnly(context, invitedDt)}')
                        : (lastSignInDt == null
                              ? 'Last sign-in • —'
                              : 'Last sign-in • ${_formatDateOnly(context, lastSignInDt)}');

                    final isSelected = _selected.contains(uid);

                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: widget.busy
                          ? null
                          : () {
                              setState(() {
                                isSelected
                                    ? _selected.remove(uid)
                                    : _selected.add(uid);
                              });
                              _notifySelection();
                            },
                      child: Material(
                        color: isSelected
                            ? AppColors.brandBlue.withOpacity(0.06)
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: theme.colorScheme.primary
                                        .withOpacity(0.10),
                                    child: Icon(
                                      isMe
                                          ? Icons.verified_user
                                          : Icons.person_outline,
                                      color: theme.colorScheme.primary,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      isMe ? '$titleName (You)' : titleName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13.5,
                                            height: 1.15,
                                          ),
                                    ),
                                  ),
                                  _actionsMenu(
                                    isMe: isMe,
                                    isInvited: isInvited,
                                    isDisabled: isDisabled,
                                    isLastAdmin: isLastAdmin,
                                    uid: uid,
                                    email: email,
                                    role: role,
                                    status: status,
                                    titleName: titleName,
                                    firstName: firstName,
                                    lastName: lastName,
                                    displayName: displayName,
                                    communications: communications,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _StatusPill(status: status),
                                  const SizedBox(width: 8),
                                  _MetaChip(
                                    icon: Icons.admin_panel_settings_outlined,
                                    text: role,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    emailLine,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    metaLine,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              if (wildixExt.isNotEmpty ||
                                  clearflyNum.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    if (wildixExt.isNotEmpty)
                                      Text(
                                        'Ext: $wildixExt',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    if (clearflyNum.isNotEmpty)
                                      Text(
                                        'Clearfly/eFax: $clearflyNum',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }

              // ✅ DESKTOP / WIDE: render enterprise table
              return _UsersTable(
                docs: filtered,
                adminCount: adminCount,
                myUid: widget.myUid,
                busy: widget.busy,
                selected: _selected,
                onToggleSelected: (uid, v) {
                  setState(() {
                    v ? _selected.add(uid) : _selected.remove(uid);
                  });
                  _notifySelection();
                },
                onToggleAll: (v) {
                  setState(() {
                    if (v) {
                      _selected.addAll(filtered.map((d) => d.id));
                    } else {
                      _selected.clear();
                    }
                  });
                },
                actionsMenuBuilder:
                    ({
                      required bool isMe,
                      required bool isInvited,
                      required bool isDisabled,
                      required bool isLastAdmin,
                      required String uid,
                      required String email,
                      required String role,
                      required String status,
                      required String titleName,
                      required String firstName,
                      required String lastName,
                      required String displayName,
                      required Map<String, dynamic> communications,
                    }) {
                      return _actionsMenu(
                        isMe: isMe,
                        isInvited: isInvited,
                        isDisabled: isDisabled,
                        isLastAdmin: isLastAdmin,
                        uid: uid,
                        email: email,
                        role: role,
                        status: status,
                        titleName: titleName,
                        firstName: firstName,
                        lastName: lastName,
                        displayName: displayName,
                        communications: communications,
                      );
                    },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.docs,
    required this.adminCount,
    required this.myUid,
    required this.busy,
    required this.selected,
    required this.onToggleSelected,
    required this.onToggleAll,
    required this.actionsMenuBuilder,
  });

  static const double _wSelect = 44;
  static const double _wName = 220;
  static const double _wEmail = 210;
  static const double _wWildix = 90;
  static const double _wClearfly = 120;
  static const double _wRole = 70;
  static const double _wStatus = 80;
  static const double _wActions = 52;

  final List<QueryDocumentSnapshot> docs;
  final int adminCount;
  final String? myUid;
  final bool busy;
  final Set<String> selected;

  final void Function(String uid, bool value) onToggleSelected;
  final void Function(bool value) onToggleAll;

  final Widget Function({
    required bool isMe,
    required bool isInvited,
    required bool isDisabled,
    required bool isLastAdmin,
    required String uid,
    required String email,
    required String role,
    required String status,
    required String titleName,
    required String firstName,
    required String lastName,
    required String displayName,
    required Map<String, dynamic> communications,
  })
  actionsMenuBuilder;

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _prettyRole(String r) {
    final v = r.toLowerCase().trim();
    if (v.isEmpty) return '—';
    return v[0].toUpperCase() + v.substring(1);
  }

  String _prettyStatus(String s) {
    final v = s.toLowerCase().trim();
    final normalized = (v == 'inactive')
        ? 'disabled'
        : (v == 'pending' ? 'invited' : v);
    if (normalized.isEmpty) return '—';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase().trim()) {
      case 'active':
        return Colors.green.shade800;
      case 'invited':
        return Colors.yellow.shade600;
      case 'disabled':
        return Colors.red.shade800;
      default:
        return const Color(0xFF475467);
    }
  }

  Widget _headerCell(ThemeData theme, String label, double width) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontSize: 12,
            color: const Color(0xFF475467),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _statusPillCompact(String rawStatus) {
    final label = _prettyStatus(rawStatus);
    final s = rawStatus.toLowerCase().trim();
    final normalized = (s == 'inactive')
        ? 'disabled'
        : (s == 'pending' ? 'invited' : s);

    Color bg;
    Color border;
    Color fg;

    switch (normalized) {
      case 'active':
        bg = Colors.green.withOpacity(0.14);
        border = Colors.green.shade700.withOpacity(0.30);
        fg = Colors.green.shade900;
        break;
      case 'invited':
        bg = Colors.amber.withOpacity(0.20);
        border = Colors.amber.shade800.withOpacity(0.28);
        fg = Colors.amber.shade900;
        break;
      case 'disabled':
        bg = Colors.red.withOpacity(0.14);
        border = Colors.red.shade700.withOpacity(0.28);
        fg = Colors.red.shade900;
        break;
      default:
        bg = Colors.grey.withOpacity(0.12);
        border = Colors.grey.shade500.withOpacity(0.25);
        fg = const Color(0xFF475467);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: 11, // ✅ compact for tight table column
          height: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final allSelected = docs.isNotEmpty && selected.length == docs.length;

    return Column(
      children: [
        // ✅ Table header row (like screenshot)
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            border: Border(
              bottom: BorderSide(color: Colors.black.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _wSelect,
                child: Checkbox(
                  value: allSelected,
                  onChanged: busy ? null : (v) => onToggleAll(v == true),
                ),
              ),
              _headerCell(theme, 'Name', _wName),
              _headerCell(theme, 'Email', _wEmail),
              _headerCell(theme, 'Wildix', _wWildix),
              _headerCell(theme, 'Clearfly', _wClearfly),
              _headerCell(theme, 'Role', _wRole),
              _headerCell(theme, 'Status', _wStatus),
              const SizedBox(width: _wActions),
            ],
          ),
        ),

        // ✅ Rows
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.black.withOpacity(0.06)),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data() as Map<String, dynamic>;

              final uid = d.id;
              final email = _s(data['email']);
              final firstName = _s(data['firstName']);
              final lastName = _s(data['lastName']);
              final displayName = _s(data['displayName']);
              final role = _s(data['role']).isEmpty
                  ? 'associate'
                  : _s(data['role']);
              final status = _s(data['status']);

              final communications = Map<String, dynamic>.from(
                data['communications'] ?? {},
              );
              final wildixExt = _s(communications['wildixExtension']);
              final clearflyNum = _s(communications['clearflySmsNumber']);

              final statusLower = status.toLowerCase().trim();
              final normalizedStatus = statusLower == 'inactive'
                  ? 'disabled'
                  : statusLower;
              final isInvited = normalizedStatus == 'invited';
              final isDisabled =
                  (data['disabled'] == true) || normalizedStatus == 'disabled';

              final isMe = myUid != null && uid == myUid;
              final isLastAdmin =
                  role.toLowerCase() == 'admin' && adminCount <= 1;

              final nameLabel = displayName.isNotEmpty
                  ? displayName
                  : ('$firstName $lastName').trim();
              final titleName = nameLabel.isNotEmpty
                  ? nameLabel
                  : (email.isNotEmpty ? email : uid);

              final isRowSelected = selected.contains(uid);

              return InkWell(
                onTap: busy
                    ? null
                    : () => onToggleSelected(uid, !isRowSelected),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  color: isRowSelected
                      ? AppColors.brandBlue.withOpacity(0.06)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      SizedBox(
                        width: _wSelect,
                        child: Checkbox(
                          value: isRowSelected,
                          onChanged: busy
                              ? null
                              : (v) => onToggleSelected(uid, v == true),
                        ),
                      ),

                      // Name (avatar + text)
                      SizedBox(
                        width: _wName,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: theme.colorScheme.primary
                                  .withOpacity(0.10),
                              child: Icon(
                                isMe
                                    ? Icons.verified_user
                                    : Icons.person_outline,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isMe ? '$titleName (You)' : titleName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF101828),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(
                        width: _wEmail,
                        child: Text(
                          email.isEmpty ? '—' : email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF475467),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      SizedBox(
                        width: _wWildix,
                        child: Text(
                          wildixExt.isEmpty ? '—' : wildixExt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF475467),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                      SizedBox(
                        width: _wClearfly,
                        child: Text(
                          clearflyNum.isEmpty ? '—' : clearflyNum,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12, // ✅ smaller text
                            color: const Color(0xFF475467),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      // ✅ Role as plain text (no pill)
                      SizedBox(
                        width: _wRole,
                        child: Text(
                          role.isEmpty ? '—' : _prettyRole(role),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: const Color(0xFF475467),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                      // ✅ Status column
                      SizedBox(
                        width: _wStatus,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit
                                .scaleDown, // ✅ ensures it never overflows
                            alignment: Alignment.centerLeft,
                            child: _statusPillCompact(status),
                          ),
                        ),
                      ),

                      SizedBox(
                        width: _wActions,
                        child: actionsMenuBuilder(
                          isMe: isMe,
                          isInvited: isInvited,
                          isDisabled: isDisabled,
                          isLastAdmin: isLastAdmin,
                          uid: uid,
                          email: email,
                          role: role,
                          status: status,
                          titleName: titleName,
                          firstName: firstName,
                          lastName: lastName,
                          displayName: displayName,
                          communications: communications,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final r = role.toLowerCase().trim();
    final isAdmin = r == 'admin';

    final bg = isAdmin
        ? const Color(0xFF111827).withOpacity(0.08)
        : AppColors.brandBlue.withOpacity(0.08);
    final fg = isAdmin ? const Color(0xFF111827) : AppColors.brandBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.20)),
      ),
      child: Text(
        isAdmin ? 'Admin' : 'Associate',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPhone = MediaQuery.of(context).size.width < 520;
    final maxChipWidth = isPhone
        ? MediaQuery.of(context).size.width * 0.60
        : 420.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxChipWidth),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isPhone ? 8 : 10,
          vertical: isPhone ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isPhone ? 13 : 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: isPhone ? 11 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase().trim();
    final isPhone = MediaQuery.of(context).size.width < 520;

    Color bg;
    Color fg;
    String label;

    switch (s) {
      case 'active':
        bg = Colors.green.withOpacity(0.12);
        fg = Colors.green.shade800;
        label = 'Active';
        break;
      case 'invited':
        bg = Colors.amber.withOpacity(0.18);
        fg = Colors.amber.shade900;
        label = 'Invited';
        break;
      case 'disabled':
        bg = Colors.red.withOpacity(0.14);
        fg = Colors.red.shade800;
        label = 'Disabled';
        break;
      default:
        bg = Colors.grey.withOpacity(0.12);
        fg = Colors.grey.shade700;
        label = status.isEmpty ? '—' : status;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isPhone ? 7 : 10,
        vertical: isPhone ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: isPhone ? 10.5 : 12,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 34),
            const SizedBox(height: 10),
            const Text('Unable to load users.'),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyBox({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
