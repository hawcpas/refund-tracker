import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // ✅ needed for VoidCallback
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

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  // =========================
  // Session Guard (auto-logout disabled users)
  // =========================

  /// ✅ Start watching session + profile. Call this once when your app starts.
  /// If the user's Firestore profile flips to disabled (or legacy inactive),
  /// we immediately sign them out to avoid "half logged in" UI states.
  void startSessionGuard({VoidCallback? onForcedLogout}) {
    // Prevent double subscriptions
    _authSub?.cancel();
    _profileSub?.cancel();

    _authSub = _auth.idTokenChanges().listen((user) async {
      // If signed out, stop watching profile.
      if (user == null) {
        await _profileSub?.cancel();
        _profileSub = null;
        return;
      }

      // ✅ NEW: Skip session guard for anonymous users (client drop-off)
      if (user.isAnonymous) {
        await _profileSub?.cancel();
        _profileSub = null;
        return;
      }

      // 1) Force refresh token -> catches disabled users quickly on refresh
      try {
        await user.getIdToken(true);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-disabled' ||
            e.code == 'user-token-expired' ||
            e.code == 'invalid-user-token') {
          await logout();
          onForcedLogout?.call();
          return;
        }
      } catch (_) {
        // ignore other errors here (network etc.)
      }

      // 2) Watch Firestore profile for status/disabled changes.
      // Cancel previous profile listener if switching users.
      await _profileSub?.cancel();

      _profileSub = _db.collection('users').doc(user.uid).snapshots().listen((
        snap,
      ) async {
        final data = snap.data() ?? {};
        final disabledFlag = data['disabled'] == true;
        final status = (data['status'] ?? '').toString().toLowerCase().trim();

        // normalize legacy statuses
        final normalizedStatus = status == 'inactive' ? 'disabled' : status;

        if (disabledFlag || normalizedStatus == 'disabled') {
          await logout();
          onForcedLogout?.call();
        }
      });
    });
  }

  Future<void> stopSessionGuard() async {
    await _authSub?.cancel();
    await _profileSub?.cancel();
    _authSub = null;
    _profileSub = null;
  }

  // =========================
  // Helpers
  // =========================

  /// ✅ Record last successful sign-in time for admin visibility.
  /// This is non-blocking and safe to call on every login.
  Future<void> _recordLastSignIn(User user) async {
    await _db.collection('users').doc(user.uid).set({
      'lastSignInAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// ✅ Promote invited -> active after first successful login.
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
    await user.reload();
    final refreshed = _auth.currentUser;

    if (refreshed == null || !refreshed.emailVerified) return;

    final ref = _db.collection('users').doc(refreshed.uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final currentStatus = (data['status'] as String?)?.toLowerCase();

      // Only auto-promote if they are currently pending (don’t override invited/admin states)
      if (currentStatus == null || currentStatus == 'invited') {
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
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc = await _db.collection('users').doc(user.uid).get();
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

      await _upsertUserProfile(user);
      await _recordLastSignIn(user);
      await _markActiveIfInvited(user);
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

  /// After successful login, promote invited -> active.
  /// Do NOT sign out unverified users — let UI route them to verify screen.
  Future<User?> login(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user == null) return null;

      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) return user;

      // Firestore updates should NEVER block login
      try {
        await _upsertUserProfile(refreshedUser);
        await _recordLastSignIn(refreshedUser);
        await _markActiveIfInvited(refreshedUser);
        await _markActiveIfEmailVerified(refreshedUser);
      } catch (e) {
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
  // ANONYMOUS AUTH (for client drop-off)
  // =========================

  /// ✅ Signs in anonymously ONLY if there is no current FirebaseAuth user.
  /// This allows "no-password" client uploads while still giving request.auth != null
  /// for Firebase Storage rules.
  Future<User?> signInAnonymouslyIfNeeded() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing;

    try {
      final cred = await _auth.signInAnonymously();
      return cred.user;
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print("ANON SIGN-IN ERROR: ${e.code} - ${e.message}");
      return null;
    } catch (e) {
      // ignore: avoid_print
      print("ANON SIGN-IN ERROR (unknown): $e");
      return null;
    }
  }

  /// Convenience helper
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  // =========================
  // LOGOUT
  // =========================

  Future<void> logout() async {
    await stopSessionGuard();
    await _auth.signOut();
  }
}
