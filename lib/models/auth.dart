enum OtpPurpose { signIn, resetPassword }

/// One OTP sent to a phone number. The server owns the attempt count,
/// lockout and resend timers; screens only display them.
class OtpChallenge {
  const OtpChallenge({
    required this.phone,
    required this.purpose,
    required this.sentAt,
    required this.resendAvailableAt,
    this.attemptsLeft = maxAttempts,
    this.lockedUntil,
  });

  static const int maxAttempts = 3;
  static const Duration resendDelay = Duration(seconds: 30);
  static const Duration lockout = Duration(seconds: 30);

  final String phone;
  final OtpPurpose purpose;
  final DateTime sentAt;
  final DateTime resendAvailableAt;
  final int attemptsLeft;
  final DateTime? lockedUntil;

  bool isLockedAt(DateTime now) {
    final until = lockedUntil;
    return until != null && now.isBefore(until);
  }

  Duration lockRemaining(DateTime now) => _until(lockedUntil, now);

  Duration resendIn(DateTime now) => _until(resendAvailableAt, now);

  bool canResendAt(DateTime now) =>
      !isLockedAt(now) && !now.isBefore(resendAvailableAt);

  OtpChallenge copyWith({
    int? attemptsLeft,
    DateTime? lockedUntil,
    bool clearLock = false,
  }) => OtpChallenge(
    phone: phone,
    purpose: purpose,
    sentAt: sentAt,
    resendAvailableAt: resendAvailableAt,
    attemptsLeft: attemptsLeft ?? this.attemptsLeft,
    lockedUntil: clearLock ? null : lockedUntil ?? this.lockedUntil,
  );

  static Duration _until(DateTime? at, DateTime now) {
    if (at == null || !now.isBefore(at)) return Duration.zero;
    return at.difference(now);
  }
}
