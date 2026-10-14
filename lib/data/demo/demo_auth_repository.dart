import '../../core/domain_events.dart';
import '../../core/failures.dart';
import '../../core/validators.dart';
import '../../models/auth.dart';
import '../../models/partner.dart';
import '../repositories/auth_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

/// Demo sign-in: any valid mobile number, OTP [demoOtp], and any email with
/// a valid password all sign in as the current demo account.
class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository(this._backend);

  static const String demoOtp = '123456';

  final DemoBackend _backend;
  final Map<OtpPurpose, OtpChallenge> _challenges = {};
  final Set<String> _resetTokens = {};

  DateTime get _now => _backend.clock.now();

  PartnerProfile _signIn() {
    final db = _backend.db;
    db.signedIn = true;
    _backend.events.emit(const ProfileChanged());
    return db.partner;
  }

  @override
  Future<PartnerProfile> signInWithEmail({
    required String email,
    required String password,
  }) => _backend.engine.run(OperationType.signIn, () {
    final error = Validators.email(email) ?? Validators.password(password);
    if (error != null) throw ValidationFailure(error);
    return _signIn();
  });

  @override
  Future<OtpChallenge> requestOtp({
    required String phone,
    required OtpPurpose purpose,
  }) => _backend.engine.run(OperationType.signIn, () {
    final number = phone.trim();
    final error = Validators.mobile(number);
    if (error != null) throw ValidationFailure(error, field: 'phone');
    final now = _now;
    final current = _challenges[purpose];
    if (current != null && current.phone == number) {
      if (current.isLockedAt(now)) {
        throw NotAllowedFailure(
          'Too many incorrect attempts. Try again in '
          '${current.lockRemaining(now).inSeconds + 1} s.',
        );
      }
      if (!current.canResendAt(now)) {
        throw NotAllowedFailure(
          'You can request a new OTP in '
          '${current.resendIn(now).inSeconds + 1} s.',
        );
      }
    }
    return _challenges[purpose] = OtpChallenge(
      phone: number,
      purpose: purpose,
      sentAt: now,
      resendAvailableAt: now.add(OtpChallenge.resendDelay),
    );
  });

  /// Applies the attempt and lockout rules; returns normally only for the
  /// correct code.
  void _checkCode(OtpPurpose purpose, String phone, String code) {
    var challenge = _challenges[purpose];
    if (challenge == null || challenge.phone != phone.trim()) {
      throw const NotAllowedFailure('Request a new OTP to continue.');
    }
    final now = _now;
    if (challenge.isLockedAt(now)) {
      throw OtpFailure(
        'Too many incorrect attempts. Try again in '
        '${challenge.lockRemaining(now).inSeconds + 1} s.',
        challenge: challenge,
      );
    }
    if (challenge.lockedUntil != null) {
      challenge = challenge.copyWith(
        attemptsLeft: OtpChallenge.maxAttempts,
        clearLock: true,
      );
    }
    if (code == demoOtp) {
      _challenges.remove(purpose);
      return;
    }
    final attemptsLeft = challenge.attemptsLeft - 1;
    if (attemptsLeft <= 0) {
      challenge = _challenges[purpose] = challenge.copyWith(
        attemptsLeft: 0,
        lockedUntil: now.add(OtpChallenge.lockout),
      );
      throw OtpFailure(
        'Incorrect OTP. Too many attempts, so OTP entry is locked for '
        '${OtpChallenge.lockout.inSeconds} s.',
        challenge: challenge,
      );
    }
    challenge = _challenges[purpose] = challenge.copyWith(
      attemptsLeft: attemptsLeft,
    );
    throw OtpFailure(
      'Incorrect OTP. $attemptsLeft '
      '${attemptsLeft == 1 ? 'attempt' : 'attempts'} left.',
      challenge: challenge,
    );
  }

  @override
  Future<PartnerProfile> verifySignInOtp({
    required String phone,
    required String code,
  }) => _backend.engine.run(OperationType.signIn, () {
    _checkCode(OtpPurpose.signIn, phone, code);
    return _signIn();
  });

  @override
  Future<String> verifyResetOtp({
    required String phone,
    required String code,
  }) => _backend.engine.run(OperationType.signIn, () {
    _checkCode(OtpPurpose.resetPassword, phone, code);
    final token = _backend.ids.next('reset');
    _resetTokens.add(token);
    return token;
  });

  @override
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) => _backend.engine.run(OperationType.signIn, () {
    final error = Validators.password(newPassword);
    if (error != null) throw ValidationFailure(error, field: 'password');
    if (!_resetTokens.remove(resetToken)) {
      throw const NotAllowedFailure(
        'This reset link has expired. Request a new OTP.',
      );
    }
  });

  @override
  Future<PartnerProfile> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) => _backend.engine.run(OperationType.signUp, () {
    final db = _backend.db;
    if (phone.trim() == db.partner.phone) {
      throw const ValidationFailure(
        'This number is already registered. Log in instead.',
        field: 'phone',
      );
    }
    db.startFresh(
      PartnerProfile(
        id: _backend.ids.next('P'),
        name: name.trim(),
        phone: phone.trim(),
        email: email.trim(),
        joinedOn: _now,
      ),
    );
    db.signedIn = true;
    _backend.events.emit(const ProfileChanged());
    _backend.events.emit(const DataReset());
    return db.partner;
  });

  @override
  Future<PartnerProfile?> restoreSession(String partnerId) =>
      _backend.engine.run(
        OperationType.restoreSession,
        () => _backend.db.partner.id == partnerId ? _signIn() : null,
      );

  @override
  Future<void> signOut() => _backend.engine.run(OperationType.signIn, () {
    _backend.db.signedIn = false;
    _challenges.clear();
  });
}
