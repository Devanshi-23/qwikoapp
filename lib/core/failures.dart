import '../models/auth.dart';

/// Typed failures thrown by repositories. Demo failure injection produces the
/// same types a real API client would.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  /// Plain-language message that can be shown to the rider.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkUnavailableFailure extends AppFailure {
  const NetworkUnavailableFailure([
    super.message = "You're offline. This needs a connection.",
  ]);
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {this.field});

  final String? field;
}

class NotAllowedFailure extends AppFailure {
  const NotAllowedFailure(super.message);
}

/// A wrong or locked OTP. [challenge] carries the updated attempts and
/// lockout so the screen can show them.
class OtpFailure extends AppFailure {
  const OtpFailure(super.message, {required this.challenge});

  final OtpChallenge challenge;
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = "We couldn't find that."]);
}

/// The offer was withdrawn, usually because another partner accepted it.
class OfferUnavailableFailure extends AppFailure {
  const OfferUnavailableFailure([
    super.message = 'This order is no longer available.',
  ]);
}

class ServerFailure extends AppFailure {
  const ServerFailure([
    super.message = 'Something went wrong on our side. Please try again.',
  ]);
}

String failureMessage(Object error) => error is AppFailure
    ? error.message
    : 'Something went wrong. Please try again.';
