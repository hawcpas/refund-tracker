import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/dashboard_cards.dart';
import '../services/auth_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _db = FirebaseFirestore.instance;
  final _authService = AuthService();

  bool _busy = false;
  String _role = '';

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await _db.collection('users').doc(user.uid).get();
    setState(() => _role = (doc.data()?['role'] ?? '').toString().toLowerCase());
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
      final callable = FirebaseFunctions.instance.httpsCallable('inviteUser');
      final res = await callable.call({
        'email': email,
        'role': role,
        'firstName': firstName,
        'lastName': lastName,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final resetLink = (data['resetLink'] ?? '').toString();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite created for ${data['email']}')),
      );

      // Show reset link immediately until email sending is wired
      if (resetLink.isNotEmpty) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Reset link (copy/paste)'),
            content: SelectableText(resetLink),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite failed: ${e.code}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteUser({
    required String uid,
    required String email,
    required String label,
  }) async {
    // UI + server both block self delete, but we also guard here.
    if (_myUid != null && uid == _myUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot delete yourself.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user'),
        content: Text('Are you sure you want to delete $label?\n\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('deleteUser');
      await callable.call({'uid': uid, 'email': email});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $label')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.code}')),
      );
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PrimaryActionCard(
            icon: Icons.person_add_alt_1,
            title: 'Invite a user',
            subtitle: 'Creates the Auth user + reset link + Firestore profile.',
            onTap: _busy ? () {} : _showInviteDialog,
          ),
          const SizedBox(height: 12),

          SettingsRow(
            icon: Icons.lock_outline,
            title: 'Invite-only access',
            subtitle: 'Self signup is disabled. Admins create accounts.',
            onTap: () {},
          ),

          const SizedBox(height: 18),
          const Text('Users', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),

          StreamBuilder<QuerySnapshot>(
            stream: _db.collection('users').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final docs = snap.data!.docs.toList();
              docs.sort((a, b) {
                final ae = ((a.data() as Map)['email'] ?? a.id).toString().toLowerCase();
                final be = ((b.data() as Map)['email'] ?? b.id).toString().toLowerCase();
                return ae.compareTo(be);
              });

              return Card(
                child: Column(
                  children: docs.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final uid = d.id;
                    final email = (data['email'] ?? '').toString();
                    final firstName = (data['firstName'] ?? '').toString();
                    final lastName = (data['lastName'] ?? '').toString();
                    final displayName = (data['displayName'] ?? '').toString();
                    final role = (data['role'] ?? 'associate').toString();
                    final status = (data['status'] ?? '').toString();

                    final isMe = (_myUid != null && uid == _myUid);
                    final nameLabel = displayName.isNotEmpty
                        ? displayName
                        : ('$firstName $lastName').trim();

                    final label = nameLabel.isNotEmpty ? '$nameLabel <$email>' : email;

                    return ListTile(
                      leading: Icon(isMe ? Icons.verified_user : Icons.person_outline),
                      title: Text(isMe ? '$label (You)' : label),
                      subtitle: Text('Role: $role • Status: $status'),
                      trailing: isMe
                          ? null
                          : IconButton(
                              tooltip: 'Delete user',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy
                                  ? null
                                  : () => _deleteUser(uid: uid, email: email, label: label),
                            ),
                    );
                  }).toList(),
                ),
              );
            },
          ),

          const SizedBox(height: 18),
          const Text('Invites', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),

          StreamBuilder<QuerySnapshot>(
            stream: _db.collection('invites').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Text('No invites.');

              return Card(
                child: Column(
                  children: docs.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final email = (data['email'] ?? d.id).toString();
                    final role = (data['role'] ?? 'associate').toString();
                    final status = (data['status'] ?? 'invited').toString();
                    final displayName = (data['displayName'] ?? '').toString();

                    return ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: Text(displayName.isNotEmpty ? '$displayName <$email>' : email),
                      subtitle: Text('Role: $role • Status: $status'),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}