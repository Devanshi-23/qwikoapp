import 'package:flutter/foundation.dart';

import '../core/failures.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/session_store.dart';
import '../models/auth.dart';
import '../models/partner.dart';
import 'active_trip_controller.dart';
import 'availability_controller.dart';
import 'loadable_controller.dart';
import 'offer_controller.dart';
import 'profile_controller.dart';

/// Sign-in state. Starting a session saves it on the device and restores
/// any active trip; ending one takes the rider offline, forgets the saved
/// session and clears every per-account controller.
class SessionController extends ChangeNotifier {
  SessionController({
    required this._auth,
    required this._store,
    required this._profile,
    required this._availability,
    required this._offers,
    required this._trip,
    required this._accountData,
  });

  final AuthRepository _auth;
  final SessionStore _store;
  final ProfileController _profile;
  final AvailabilityController _availability;
  final OfferController _offers;
  final ActiveTripController _trip;
  final List<LoadableController> _accountData;

  bool _signedIn = false;
  bool _busy = false;
  OtpChallenge? _otp;

  bool get isSignedIn => _signedIn;

  bool get isBusy => _busy;

  PartnerProfile? get partner => _profile.profile;

  /// The OTP currently being entered, for sign-in or password reset.
  OtpChallenge? get otpChallenge => _otp;

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_busy) throw const NotAllowedFailure('Please wait a moment.');
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<PartnerProfile> signInWithEmail({
    required String email,
    required String password,
  }) => _run(() async {
    final profile = await _auth.signInWithEmail(
      email: email,
      password: password,
    );
    await _start(profile);
    return profile;
  });

  Future<OtpChallenge> requestOtp(String phone, OtpPurpose purpose) => _run(
    () async {
      final challenge = await _auth.requestOtp(phone: phone, purpose: purpose);
      _otp = challenge;
      return challenge;
    },
  );

  /// Sends a new code to the number of the current challenge.
  Future<OtpChallenge> resendOtp() {
    final current = _otp;
    if (current == null) {
      throw const NotAllowedFailure('Request a new OTP to continue.');
    }
    return requestOtp(current.phone, current.purpose);
  }

  Future<T> _verify<T>(Future<T> Function(String phone) verify) =>
      _run(() async {
        final current = _otp;
        if (current == null) {
          throw const NotAllowedFailure('Request a new OTP to continue.');
        }
        try {
          final result = await verify(current.phone);
          _otp = null;
          return result;
        } on OtpFailure catch (failure) {
          _otp = failure.challenge;
          rethrow;
        }
      });

  Future<PartnerProfile> verifySignInOtp(String code) => _verify((phone) async {
    final profile = await _auth.verifySignInOtp(phone: phone, code: code);
    await _start(profile);
    return profile;
  });

  /// Returns the token for [resetPassword].
  Future<String> verifyResetOtp(String code) =>
      _verify((phone) => _auth.verifyResetOtp(phone: phone, code: code));

  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) => _run(
    () => _auth.resetPassword(resetToken: resetToken, newPassword: newPassword),
  );

  /// Re-reads the partner, e.g. after verification or a demo account switch.
  Future<PartnerProfile> refreshPartner() async {
    await _profile.load();
    final profile = _profile.profile;
    if (profile == null) {
      throw ServerFailure(_profile.error ?? "We couldn't load your profile.");
    }
    return profile;
  }

  Future<PartnerProfile> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) => _run(() async {
    final profile = await _auth.signUp(
      name: name,
      email: email,
      phone: phone,
      password: password,
    );
    await _start(profile);
    return profile;
  });

  /// Signs back in from the session saved on this device; works offline.
  /// Returns false when there is none or it no longer matches an account.
  Future<bool> restore() async {
    if (_signedIn) return true;
    final saved = await _store.read();
    if (saved == null) return false;
    final PartnerProfile? profile;
    try {
      profile = await _auth.restoreSession(saved.partnerId);
    } on AppFailure {
      return false;
    }
    if (profile == null) {
      await _store.clear();
      return false;
    }
    await _start(profile);
    notifyListeners();
    return true;
  }

  Future<void> _start(PartnerProfile profile) async {
    _profile.setProfile(profile);
    _signedIn = true;
    await _store.write(SavedSession(partnerId: profile.id));
    try {
      await _trip.restore();
    } on AppFailure {
      // The home screen offers a retry if the trip could not be restored.
    }
    _offers.enabled = true;
    _availability.loadActivity();
  }

  Future<void> signOut() => _run(() async {
    if (_trip.hasTrip) {
      throw const NotAllowedFailure(
        'Finish your current order before logging out.',
      );
    }
    if (_availability.isOnline) await _availability.goOffline();
    await _auth.signOut();
    await _store.clear();
    _signedIn = false;
    _otp = null;
    _offers.enabled = false;
    _availability.reset();
    _trip.reset();
    _profile.reset();
    for (final controller in _accountData) {
      controller.reset();
    }
  });
}
