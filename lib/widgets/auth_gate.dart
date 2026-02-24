import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthGate extends StatelessWidget {
  final Widget child;
  final bool requireAdmin;

  const AuthGate({
    super.key,
    required this.child,
    this.requireAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // ✅ Not signed in
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
      return const SizedBox.shrink();
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server)),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data!.data() ?? {};
        final status = (data['status'] ?? '').toString().toLowerCase();
        final role = (data['role'] ?? '').toString().toLowerCase();
        final disabled = data['disabled'] == true || status == 'disabled';

        // ✅ Disabled user → login
        if (disabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/login');
          });
          return const SizedBox.shrink();
        }

        // ✅ Email not verified → verify screen
        if (!user.emailVerified) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/verify-email');
          });
          return const SizedBox.shrink();
        }

        // ✅ Admin-only route
        if (requireAdmin && role != 'admin') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          });
          return const SizedBox.shrink();
        }

        // ✅ Allowed
        return child;
      },
    );
  }
}