import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/centered_section.dart';
import '../widgets/dashboard_cards.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _db = FirebaseFirestore.instance;

  bool _busy = false;

  bool _roleLoading = true;
  String _role = '';
  String? _roleError;

  final _userSearchCtrl = TextEditingController();
  String get _userQuery => _userSearchCtrl.text.trim().toLowerCase();

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

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

      final doc = await _db
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));

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

  bool get _isAdmin => _role == 'admin';

  // -------------------------
  // Cloud Function helpers
  // -------------------------
  HttpsCallable _callable(String name) {
    return FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(name);
  }

  Future<void> _updateUser({
    required String uid,
    required String email,
    required String role,
    required String status,
    required String reason,
  }) async {
    setState(() => _busy = true);
    try {
      await _callable('updateUser').call({
        'uid': uid,
        'email': email,
        'role': role,
        'status': status,
        'reason': reason,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User updated')),
      );
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
      await _callable('setUserDisabled').call({
        'uid': uid,
        'disabled': disabled,
        'reason': reason,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(disabled ? 'User deactivated' : 'User reactivated')),
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
      await _callable('sendPasswordReset').call({
        'uid': uid,
        'email': email,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset sent to $email')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite resent to $email')),
      );
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
  }) async {
    final emailCtrl = TextEditingController(text: currentEmail);

    String role = (currentRole.isEmpty ? 'associate' : currentRole).toLowerCase().trim();
    String status = (currentStatus.isEmpty ? 'active' : currentStatus).toLowerCase().trim();

    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit user'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
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
          ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email')),
      );
      return;
    }

    await _updateUser(
      uid: uid,
      email: email,
      role: role,
      status: status,
      reason: reasonCtrl.text.trim(),
    );
  }

  // -------------------------
  // Existing functions
  // -------------------------
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User created for $invitedEmail')),
      );
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
        content: Text('Are you sure you want to delete $label?\n\nThis cannot be undone.'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $label')),
      );
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
    if (_roleLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin • Users')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_roleError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin • Users')),
        body: Center(
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
                FilledButton(
                  onPressed: _loadMyRole,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(child: Text('Access restricted. Admins only.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin • Users'),
        actions: [
          IconButton(
            tooltip: 'Invite user',
            onPressed: _busy ? null : _showInviteDialog,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: Stack(
        children: [
          CenteredSection(
            maxWidth: 1100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        PrimaryActionCard(
                          icon: Icons.person_add_alt_1,
                          title: 'Invite a user',
                          subtitle: 'Creates the Auth user + reset link + Firestore profile.',
                          onTap: _busy ? () {} : _showInviteDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 620),
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
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}

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
          color: active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.35))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Search users by name or email…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 6,
            children: [
              chip('All', 'all'),
              chip('Active', 'active'),
              chip('Invited', 'invited'),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsersPane extends StatefulWidget {
  final FirebaseFirestore db;
  final String? myUid;
  final bool busy;
  final String query;
  final TextEditingController searchCtrl;

  final Future<void> Function({
    required String uid,
    required String email,
    required String label,
    required String targetRole,
    required bool isLastAdmin,
  }) onDeleteUser;

  final Future<void> Function({
    required String uid,
    required String currentEmail,
    required String currentRole,
    required String currentStatus,
  }) onEditUser;

  final Future<void> Function({required String uid}) onResendInvite;

  final Future<void> Function({required String uid, required String email}) onSendPasswordReset;

  final Future<void> Function({required String uid, required bool disabled, required String reason}) onSetDisabled;

  final Future<String?> Function({required String title, required String hint}) promptReason;

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
  });

  @override
  State<_UsersPane> createState() => _UsersPaneState();
}

class _UsersPaneState extends State<_UsersPane> {
  String _statusFilter = 'all'; // all | active | invited

  String _formatDateTime(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final dateStr = loc.formatShortDate(dt);
    final timeStr = loc.formatTimeOfDay(TimeOfDay.fromDateTime(dt));
    return '$dateStr • $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SearchHeader(
          controller: widget.searchCtrl,
          selected: _statusFilter,
          onSelected: (v) => setState(() => _statusFilter = v),
        ),
        const Divider(height: 1),

        Flexible(
          fit: FlexFit.loose,
          child: StreamBuilder<QuerySnapshot>(
            stream: widget.db.collection('users').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return _ErrorBox(error: snap.error.toString());
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final docs = snap.data!.docs.toList();

              final adminCount = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['role'] ?? '').toString().toLowerCase() == 'admin';
              }).length;

              docs.sort((a, b) {
                final ae = ((a.data() as Map)['email'] ?? a.id).toString().toLowerCase();
                final be = ((b.data() as Map)['email'] ?? b.id).toString().toLowerCase();
                return ae.compareTo(be);
              });

              final filtered = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final email = (data['email'] ?? '').toString().toLowerCase();
                final fn = (data['firstName'] ?? '').toString().toLowerCase();
                final ln = (data['lastName'] ?? '').toString().toLowerCase();
                final dn = (data['displayName'] ?? '').toString().toLowerCase();
                final status = (data['status'] ?? '').toString().toLowerCase();

                final matchesSearch = widget.query.isEmpty || ('$email $fn $ln $dn').contains(widget.query);
                final matchesStatus = _statusFilter == 'all' || status == _statusFilter;

                return matchesSearch && matchesStatus;
              }).toList();

              if (filtered.isEmpty) {
                return const _EmptyBox(
                  icon: Icons.group_outlined,
                  title: 'No users found',
                  subtitle: 'Try adjusting your search or filter.',
                );
              }

              return SingleChildScrollView(
                child: ListView.separated(
                  padding: const EdgeInsets.all(8),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
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

                    final statusLower = status.toLowerCase().trim();
                    final isInvited = statusLower == 'invited';

                    final isDisabled = (data['disabled'] == true) || statusLower == 'inactive';

                    DateTime? invitedDt;
                    final invitedAt = data['invitedAt'];
                    if (invitedAt is Timestamp) invitedDt = invitedAt.toDate();

                    DateTime? lastSignInDt;
                    final lastSignInAt = data['lastSignInAt'];
                    if (lastSignInAt is Timestamp) lastSignInDt = lastSignInAt.toDate();

                    final isMe = widget.myUid != null && uid == widget.myUid;

                    final nameLabel = displayName.isNotEmpty ? displayName : ('$firstName $lastName').trim();
                    final label = nameLabel.isNotEmpty ? '$nameLabel <$email>' : email;

                    final isLastAdmin = role.toLowerCase() == 'admin' && adminCount <= 1;

                    final Widget details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isInvited)
                          Text('Role: $role',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
                        if (isInvited)
                          Text(
                            invitedDt == null ? 'Invited: —' : 'Invited: ${_formatDateTime(context, invitedDt)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                          ),
                        if (!isInvited)
                          Text(
                            lastSignInDt == null
                                ? 'Last sign-in: —'
                                : 'Last sign-in: ${_formatDateTime(context, lastSignInDt)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                          ),
                      ],
                    );

                    return ListTile(
                      dense: true,
                      leading: Icon(isMe ? Icons.verified_user : Icons.person_outline),
                      title: Text(isMe ? '$label (You)' : label),
                      subtitle: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatusPill(status: status),
                          const SizedBox(width: 8),
                          Expanded(child: details),
                        ],
                      ),

                      // ✅ NEW: ⋮ actions menu instead of only delete
                      trailing: isMe
                          ? null
                          : PopupMenuButton<String>(
                              tooltip: 'Actions',
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) async {
                                if (widget.busy) return;

                                if (value == 'edit') {
                                  await widget.onEditUser(
                                    uid: uid,
                                    currentEmail: email,
                                    currentRole: role,
                                    currentStatus: status,
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
                                      const SnackBar(content: Text('You cannot deactivate the last admin.')),
                                    );
                                    return;
                                  }
                                  final reason = await widget.promptReason(
                                    title: 'Deactivate user',
                                    hint: 'Reason (audit note)',
                                  );
                                  if (reason == null) return;

                                  await widget.onSetDisabled(uid: uid, disabled: true, reason: reason);
                                } else if (value == 'reactivate') {
                                  final reason = await widget.promptReason(
                                    title: 'Reactivate user',
                                    hint: 'Reason (audit note)',
                                  );
                                  if (reason == null) return;

                                  await widget.onSetDisabled(uid: uid, disabled: false, reason: reason);
                                } else if (value == 'delete') {
                                  await widget.onDeleteUser(
                                    uid: uid,
                                    email: email,
                                    label: label,
                                    targetRole: role,
                                    isLastAdmin: isLastAdmin,
                                  );
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit user')),
                                const PopupMenuItem(value: 'resetPassword', child: Text('Send password reset')),
                                if (isInvited) const PopupMenuItem(value: 'resendInvite', child: Text('Resend invite')),
                                const PopupMenuDivider(),
                                if (isDisabled)
                                  const PopupMenuItem(value: 'reactivate', child: Text('Reactivate'))
                                else
                                  PopupMenuItem(
                                    value: 'deactivate',
                                    enabled: !isLastAdmin,
                                    child: Text(isLastAdmin ? 'Deactivate (not allowed)' : 'Deactivate'),
                                  ),
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'delete',
                                  enabled: !isLastAdmin,
                                  child: Text(isLastAdmin ? 'Delete (not allowed)' : 'Delete user'),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase().trim();

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
      case 'inactive':
        bg = Colors.grey.withOpacity(0.14);
        fg = Colors.grey.shade800;
        label = 'Inactive';
        break;
      default:
        bg = Colors.grey.withOpacity(0.12);
        fg = Colors.grey.shade700;
        label = status.isEmpty ? '—' : status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12),
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
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}