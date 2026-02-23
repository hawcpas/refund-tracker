import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';
import 'dart:async';

/// Simple result wrapper so UI can show professional error messages.
class AuthResult<T> {
  final T? data;
  final String? code; // FirebaseAuthException.code
  final String? message;

  const AuthResult({this.data, this.code, this.message});

  bool get isSuccess => code == null;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // =========================
  // Helpers
  // =========================

  /// ✅ NEW: Promote invited -> active after first successful login.
  /// Safe: Only transitions invited -> active (won’t override admin-applied states).
  Future<void> _markActiveIfInvited(User user) async {
    final ref = _db.collection('users').doc(user.uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data() ?? {};
      final status = (data['status'] as String?)?.toLowerCase();

      if (status == 'invited') {
        tx.set(ref, {
          'status': 'active',
          'activatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  /// Existing: mark emailVerified in Firestore and optionally promote pending -> active.
  /// (Kept your original behavior, but now it ALSO avoids overriding invited status here.)
  Future<void> _markActiveIfEmailVerified(User user) async {
    // Make sure we have the latest emailVerified state
    await user.reload();
    final refreshed = _auth.currentUser;

    if (refreshed == null || !refreshed.emailVerified) return;

    final ref = _db.collection('users').doc(refreshed.uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final currentStatus = (data['status'] as String?)?.toLowerCase();

      // Only auto-promote if they are currently pending (don’t override invited/admin states)
      if (currentStatus == null || currentStatus == 'pending') {
        tx.set(ref, {
          'status': 'active',
          'emailVerified': true,
          'verifiedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // Still record that email is verified, without changing status
        tx.set(ref, {
          'emailVerified': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  Future<UserProfile?> getCurrentUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists) return null;

    final data = doc.data()!;
    return UserProfile(
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      email: data['email'] ?? user.email ?? '',
    );
  }

  /// Ensures a user profile document exists in Firestore.
  /// Uses merge to avoid overwriting existing fields.
  Future<void> _upsertUserProfile(
    User user, {
    String? firstName,
    String? lastName,
  }) async {
    final String? email = user.email;
    final String displayNameFromAuth = (user.displayName ?? '').trim();

    final String fn = (firstName ?? '').trim();
    final String ln = (lastName ?? '').trim();
    final String computedDisplayName =
        ('${fn.isNotEmpty ? fn : ''} ${ln.isNotEmpty ? ln : ''}').trim();

    final String finalDisplayName = computedDisplayName.isNotEmpty
        ? computedDisplayName
        : displayNameFromAuth;

    await _db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': email,
      if (fn.isNotEmpty) 'firstName': fn,
      if (ln.isNotEmpty) 'lastName': ln,
      if (finalDisplayName.isNotEmpty) 'displayName': finalDisplayName,
      'updatedAt': FieldValue.serverTimestamp(),
      // ✅ DO NOT set role/status here
    }, SetOptions(merge: true));
  }

  // =========================
  // SEND PASSWORD RESET EMAIL
  // =========================

  /// Returns null on success, otherwise returns FirebaseAuthException.code
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print("PASSWORD RESET ERROR: ${e.code} - ${e.message}");
      return e.code;
    } catch (e) {
      // ignore: avoid_print
      print("PASSWORD RESET ERROR (unknown): $e");
      return 'unknown-error';
    }
  }

  // =========================
  // GOOGLE SIGN-IN
  // =========================

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      // Ensure profile exists/updated for Google sign-ins too
      await _upsertUserProfile(user);

      // ✅ If they were invited (rare for Google), promote on first login
      await _markActiveIfInvited(user);

      // ✅ If verified, record it (won’t override invited/admin states)
      await _markActiveIfEmailVerified(user);

      return user;
    } catch (e) {
      // ignore: avoid_print
      print("GOOGLE SIGN-IN ERROR: $e");
      return null;
    }
  }

  // =========================
  // LOGIN (Email/Password)
  // =========================

  /// ✅ UPDATED: After successful login, promote invited -> active.
  /// Do NOT sign out unverified users — let UI route them to verify screen.
  Future<User?> login(String email, String password) async {
    try {
      // 1) Auth sign-in (this is the only thing that should decide login success)
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user == null) return null;

      // Refresh verification state
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) return user;

      // 2) Firestore updates should NEVER block login
      try {
        await _upsertUserProfile(refreshedUser);

        // Promote invited -> active on first successful login
        await _markActiveIfInvited(refreshedUser);

        // Keep your existing behavior (optional)
        await _markActiveIfEmailVerified(refreshedUser);
      } catch (e) {
        // IMPORTANT: don't fail login because Firestore updates failed
        // ignore: avoid_print
        print("Post-login Firestore update failed (non-blocking): $e");
      }

      return refreshedUser;
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print("LOGIN AUTH ERROR: ${e.code} - ${e.message}");
      return null;
    } catch (e) {
      // ignore: avoid_print
      print("LOGIN ERROR (unknown): $e");
      return null;
    }
  }

  // =========================
  // SIGNUP (Email/Password + Profile)
  // =========================

  /// Signup detailed - unchanged from your version
  Future<AuthResult<User>> signupDetailed(
    String email,
    String password, {
    String firstName = '',
    String lastName = '',
  }) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user == null) {
        return const AuthResult<User>(
          data: null,
          code: 'no-user',
          message: 'Account was created but no user was returned.',
        );
      }

      final fn = firstName.trim();
      final ln = lastName.trim();
      final displayName =
          ('${fn.isNotEmpty ? fn : ''} ${ln.isNotEmpty ? ln : ''}').trim();

      if (displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }

      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'firstName': fn,
        'lastName': ln,
        'displayName': displayName.isNotEmpty
            ? displayName
            : (user.displayName ?? ''),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'role': 'associate',
        'status': 'pending',
      }, SetOptions(merge: true));

      await user.sendEmailVerification();

      return AuthResult<User>(data: user);
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print("SIGNUP AUTH ERROR: ${e.code} - ${e.message}");
      return AuthResult<User>(data: null, code: e.code, message: e.message);
    } on FirebaseException catch (e) {
      // ignore: avoid_print
      print("SIGNUP FIRESTORE ERROR: ${e.code} - ${e.message}");
      return AuthResult<User>(data: null, code: e.code, message: e.message);
    } catch (e) {
      // ignore: avoid_print
      print("SIGNUP ERROR (unknown): $e");
      return const AuthResult<User>(
        data: null,
        code: 'unknown-error',
        message: 'Unknown error occurred during signup.',
      );
    }
  }

  /// Compatibility method
  Future<User?> signup(String email, String password) async {
    final result = await signupDetailed(email, password);
    return result.data;
  }

  // =========================
  // RESEND VERIFICATION EMAIL
  // =========================

  Future<String?> resendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'no-current-user';

      await user.sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print("RESEND VERIFICATION ERROR: ${e.code} - ${e.message}");
      return e.code;
    } catch (e) {
      // ignore: avoid_print
      print("RESEND VERIFICATION ERROR (unknown): $e");
      return 'unknown-error';
    }
  }

  // =========================
  // CHECK VERIFICATION STATUS
  // =========================

  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    await user.reload();
    final refreshed = _auth.currentUser;
    final verified = refreshed?.emailVerified ?? false;

    if (verified && refreshed != null) {
      await _markActiveIfEmailVerified(refreshed);
    }

    return verified;
  }

  // =========================
  // UPDATE PASSWORD
  // =========================

  /// Returns null on success, otherwise returns FirebaseAuthException.code
  Future<String?> updatePassword(String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'no-current-user';

      await user.updatePassword(newPassword);
      await user.reload();
      return null;
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print("UPDATE PASSWORD ERROR: ${e.code} - ${e.message}");
      return e.code;
    } catch (e) {
      // ignore: avoid_print
      print("UPDATE PASSWORD ERROR (unknown): $e");
      return 'unknown-error';
    }
  }

  // =========================
  // LOGOUT
  // =========================

  Future<void> logout() async {
    await _auth.signOut();
  }
}
