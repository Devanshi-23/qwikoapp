import '../../models/auth.dart';
import '../../models/partner.dart';

abstract interface class AuthRepository {
  Future<PartnerProfile> signInWithEmail({
    required String email,
    required String password,
  });

  /// Sends a 6-digit OTP. Also used to resend once
  /// [OtpChallenge.resendAvailableAt] has passed.
  Future<OtpChallenge> requestOtp({
    required String phone,
    required OtpPurpose purpose,
  });

  /// Throws [OtpFailure] for a wrong code or while locked out.
  Future<PartnerProfile> verifySignInOtp({
    required String phone,
    required String code,
  });

  /// Returns a token that authorises one password reset.
  Future<String> verifyResetOtp({required String phone, required String code});

  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  });

  Future<PartnerProfile> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  });

  /// Signs back in from a session saved on this device, without the
  /// network. Null when the session no longer matches an account.
  Future<PartnerProfile?> restoreSession(String partnerId);

  Future<void> signOut();
}
