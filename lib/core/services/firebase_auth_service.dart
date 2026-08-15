import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseAuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in anonymously (if guest flow is activated)
  Future<UserCredential> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Anonymous Error: ${e.message}');
      rethrow;
    }
  }

  // Sign in with Email and Password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Email Login Error: ${e.message}');
      rethrow;
    }
  }

  // Verify Phone Number (Sends OTP code)
  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(FirebaseAuthException e) onVerificationFailed,
    required Function(PhoneAuthCredential credential) onVerificationCompleted,
    int? forceResendingToken,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber.trim(),
        verificationCompleted: onVerificationCompleted,
        verificationFailed: onVerificationFailed,
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('Verification code timeout: $verificationId');
        },
        forceResendingToken: forceResendingToken,
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      debugPrint('Firebase Phone Verification Trigger Error: $e');
      rethrow;
    }
  }

  // Sign in with Phone SMS Code
  Future<UserCredential> signInWithPhoneOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth OTP Verify Error: ${e.message}');
      rethrow;
    }
  }

  // Securely get valid JWT ID Token (auto-refresh supported by SDK)
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (currentUser == null) return null;
    try {
      return await currentUser!.getIdToken(forceRefresh);
    } catch (e) {
      debugPrint('Error fetching ID Token: $e');
      return null;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Firebase Sign Out Error: $e');
      rethrow;
    }
  }
}
