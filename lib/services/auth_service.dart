import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
      // UI will redirect to /verify-email
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

  // SIGNUP (Email/Password)
  // Key change: send verification email after creating the account.
  Future<User?> signup(String email, String password) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user == null) return null;

      // ✅ Send verification email
      await user.sendEmailVerification();

      return user;
    } catch (e) {
      print("SIGNUP ERROR: $e");
      return null;
    }
  }

  // RESEND VERIFICATION EMAIL
  // Returns null on success, otherwise returns the FirebaseAuthException code.
  Future<String?> resendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'no-current-user';

      await user.sendEmailVerification();
      return null; // success
    } on FirebaseAuthException catch (e) {
      // Common codes include: too-many-requests, operation-not-allowed,
      // network-request-failed, invalid-email, etc.
      print("RESEND VERIFICATION ERROR: ${e.code} - ${e.message}");
      return e.code;
    } catch (e) {
      print("RESEND VERIFICATION ERROR (unknown): $e");
      return 'unknown-error';
    }
  }

  // CHECK VERIFICATION STATUS (use on a "I've verified" / "Refresh" button)
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
      return null; // success
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
