import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  // SEND PASSWORD RESET EMAIL
  // Returns null on success, otherwise returns FirebaseAuthException.code
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null; // success
    } on FirebaseAuthException catch (e) {
      print("PASSWORD RESET ERROR: ${e.code} - ${e.message}");
      return e.code;
    } catch (e) {
      print("PASSWORD RESET ERROR (unknown): $e");
      return 'unknown-error';
    }
  }

  // GOOGLE SIGN-IN
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
      return userCredential.user;
    } catch (e) {
      print("GOOGLE SIGN-IN ERROR: $e");
      return null;
    }
  }

  // LOGIN (Email/Password)
  // Do NOT sign out unverified users — let UI route them to verify screen.
  Future<User?> login(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user == null) return null;

      // Refresh verification state
      await user.reload();
      final refreshedUser = _auth.currentUser;

      // If not verified, keep user signed in
      if (refreshedUser != null && !refreshedUser.emailVerified) {
        return refreshedUser;
      }

      return refreshedUser;
    } catch (e) {
      print("LOGIN ERROR: $e");
      return null;
    }
  }

  // CHECK IF USER EXISTS
  Future<bool> userExists(String email) async {
    try {
      final methods = await _auth.fetchSignInMethodsForEmail(email);
      return methods.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// ✅ NEW: SIGNUP with explicit error code support for UI
  /// Returns AuthResult<User> where:
  /// - result.data is the created user (on success)
  /// - result.code is FirebaseAuthException.code (on failure)
  Future<AuthResult<User>> signupDetailed(String email, String password) async {
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

      // Send verification email
      await user.sendEmailVerification();

      return AuthResult<User>(data: user);
    } on FirebaseAuthException catch (e) {
      print("SIGNUP ERROR: ${e.code} - ${e.message}");
      return AuthResult<User>(data: null, code: e.code, message: e.message);
    } catch (e) {
      print("SIGNUP ERROR (unknown): $e");
      return const AuthResult<User>(data: null, code: 'unknown-error');
    }
  }

  /// ✅ Keep old signature for compatibility (calls signupDetailed internally)
  Future<User?> signup(String email, String password) async {
    final result = await signupDetailed(email, password);
    return result.data;
  }

  // RESEND VERIFICATION EMAIL
  Future<String?> resendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'no-current-user';

      await user.sendEmailVerification();
      return null; // success
    } on FirebaseAuthException catch (e) {
      print("RESEND VERIFICATION ERROR: ${e.code} - ${e.message}");
      return e.code;
    } catch (e) {
      print("RESEND VERIFICATION ERROR (unknown): $e");
      return 'unknown-error';
    }
  }

  // CHECK VERIFICATION STATUS
  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // Returns null on success, otherwise returns FirebaseAuthException.code
  Future<String?> updatePassword(String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'no-current-user';

      await user.updatePassword(newPassword);
      await user.reload();
      return null;
    } on FirebaseAuthException catch (e) {
      print("UPDATE PASSWORD ERROR: ${e.code} - ${e.message}");
      return e.code;
    } catch (e) {
      print("UPDATE PASSWORD ERROR (unknown): $e");
      return 'unknown-error';
    }
  }

  // LOGOUT
  Future<void> logout() async {
    await _auth.signOut();
  }
}