import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

// Client ID yang anda berikan
const _webClientId = '413886281936-k2pkrgk0f80o7ust7tk8e646lffun9sn.apps.googleusercontent.com';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Isytihar GoogleSignIn secara statik atau global
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _webClientId,
  );

  User? get currentUser => _supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'Gagal mendapatkan ID token dari Google';
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // Kemaskini OneSignal Tags selepas login
      final user = _supabase.auth.currentUser;
      if (user != null) {
        // Simpan Google Avatar URL secara eksplisit untuk fungsi restore nanti
        if (googleUser.photoUrl != null) {
          await _supabase.auth.updateUser(
            UserAttributes(
              data: {'google_avatar_url': googleUser.photoUrl},
            ),
          );
        }

        final bool isAdmin = user.userMetadata?['is_admin'] == true;
        final bool isModerator = user.userMetadata?['is_moderator'] == true;
        final bool isYB = user.userMetadata?['is_yb'] == true;
        
        if (isAdmin || isModerator || isYB) {
          OneSignal.User.addTagWithKey("role", "admin_staff");
        } else {
          OneSignal.User.removeTag("role");
        }
        
        // Login OneSignal dengan User ID (External ID)
        OneSignal.login(user.id);
        
        // Sentiasa set user_id tag (optional but good for filtering)
        OneSignal.User.addTagWithKey("user_id", user.id);
      }
    } catch (e) {
      debugPrint('Error Google Sign In: $e');
      rethrow;
    }
  }

  Future<void> sendOTP(String phone) async {
    try {
      await _supabase.auth.signInWithOtp(
        phone: phone,
      );
    } catch (e) {
      debugPrint('Error sending OTP: $e');
      rethrow;
    }
  }

  Future<void> verifyOTP(String phone, String token) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        phone: phone,
        token: token,
        type: OtpType.sms,
      );
      
      if (response.user != null) {
        // Tandakan sebagai verified dalam metadata
        await _supabase.auth.updateUser(
          UserAttributes(
            data: {'phone_verified': true},
          ),
        );
      }
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      await _googleSignIn.signOut();
      OneSignal.User.removeTag("role");
      OneSignal.logout();
    } catch (e) {
      debugPrint('Error Sign Out: $e');
    }
  }
}
