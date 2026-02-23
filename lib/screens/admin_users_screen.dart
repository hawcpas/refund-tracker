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

      // Force server read (avoids stale cache)
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

  Future<void> _inviteUser({
    required String email,
    required String role,
    required String firstName,
    required String lastName,
  }) async {
    setState(() => _busy = true);

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('inviteUser');

      final res = await callable.call({
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
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('deleteUser');

      await callable.call({'uid': uid, 'email': email});

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
                  // ✅ LEFT: Invite action panel (fixed width)
                  SizedBox(
                    width: 360, // ← adjust between 320–420 if you want
                    child: Column(
                      children: [
                        PrimaryActionCard(
                          icon: Icons.person_add_alt_1,
                          title: 'Invite a user',
                          subtitle:
                              'Creates the Auth user + reset link + Firestore profile.',
                          onTap: _busy ? () {} : _showInviteDialog,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 16),

                  // ✅ RIGHT: Users list (fills remaining space)
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
          color: active
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.35)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          // ✅ SEARCH
          Expanded(
            child: TextField(
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
            ),
          ),

          const SizedBox(width: 12),

          // ✅ STATUS FILTER CHIPS
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
  })
  onDeleteUser;

  const _UsersPane({
    required this.db,
    required this.myUid,
    required this.busy,
    required this.query,
    required this.searchCtrl,
    required this.onDeleteUser,
  });

  @override
  State<_UsersPane> createState() => _UsersPaneState();
}

class _UsersPaneState extends State<_UsersPane> {
  String _statusFilter = 'all'; // all | active | invited

  String _formatInviteDateTime(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final dateStr = loc.formatShortDate(dt);
    final timeStr = loc.formatTimeOfDay(TimeOfDay.fromDateTime(dt));
    return '$dateStr • $timeStr';
  }

  String _formatLastSignIn(BuildContext context, DateTime dt) {
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
        // ✅ SEARCH + FILTER HEADER
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
              if (snap.hasError) {
                return _ErrorBox(error: snap.error.toString());
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs.toList();

              final adminCount = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['role'] ?? '').toString().toLowerCase() == 'admin';
              }).length;

              // ✅ SORT
              docs.sort((a, b) {
                final ae = ((a.data() as Map)['email'] ?? a.id)
                    .toString()
                    .toLowerCase();
                final be = ((b.data() as Map)['email'] ?? b.id)
                    .toString()
                    .toLowerCase();
                return ae.compareTo(be);
              });

              // ✅ SEARCH + STATUS FILTER
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

                    final isInvited = status.toLowerCase() == 'invited';

                    DateTime? invitedDt;
                    final invitedAt = data['invitedAt'];
                    if (invitedAt is Timestamp) {
                      invitedDt = invitedAt.toDate();
                    }

                    DateTime? lastSignInDt;
                    final lastSignInAt = data['lastSignInAt'];
                    if (lastSignInAt is Timestamp) {
                      lastSignInDt = lastSignInAt.toDate();
                    }

                    final isMe = widget.myUid != null && uid == widget.myUid;

                    final nameLabel = displayName.isNotEmpty
                        ? displayName
                        : ('$firstName $lastName').trim();
                    final label = nameLabel.isNotEmpty
                        ? '$nameLabel <$email>'
                        : email;

                    final isLastAdmin =
                        role.toLowerCase() == 'admin' && adminCount <= 1;
                    final disableDelete = widget.busy || isMe || isLastAdmin;

                    // ✅ Detail lines under the status pill
                    final Widget details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Always show role for non-invited users
                        if (!isInvited)
                          Text(
                            'Role: $role',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),

                        // If invited (not signed in yet), show invited timestamp
                        if (isInvited)
                          Text(
                            invitedDt == null
                                ? 'Invited: —'
                                : 'Invited: ${_formatInviteDateTime(context, invitedDt)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),

                        // If not invited, show last sign-in timestamp
                        if (!isInvited)
                          Text(
                            lastSignInDt == null
                                ? 'Last sign-in: —'
                                : 'Last sign-in: ${_formatLastSignIn(context, lastSignInDt)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                      ],
                    );

                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isMe ? Icons.verified_user : Icons.person_outline,
                      ),
                      title: Text(isMe ? '$label (You)' : label),
                      subtitle: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatusPill(status: status),
                          const SizedBox(width: 8),
                          Expanded(child: details),
                        ],
                      ),
                      trailing: isMe
                          ? null
                          : IconButton(
                              tooltip: isLastAdmin
                                  ? 'Cannot delete the last admin'
                                  : 'Delete user',
                              icon: Icon(
                                Icons.delete_outline,
                                color: isLastAdmin
                                    ? Colors.grey
                                    : Colors.red.shade700,
                              ),
                              onPressed: disableDelete
                                  ? null
                                  : () => widget.onDeleteUser(
                                      uid: uid,
                                      email: email,
                                      label: label,
                                      targetRole: role,
                                      isLastAdmin: isLastAdmin,
                                    ),
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
        // ✅ Yellow-ish that is still readable
        bg = Colors.amber.withOpacity(0.18);
        fg = Colors.amber.shade900;
        label = 'Invited';
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

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _SearchBar({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      // ✅ Distinct background just for the search section
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.35)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.35)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.35)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 1.6,
            ),
          ),
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
