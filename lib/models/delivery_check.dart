import 'dart:math' as math;

import '../core/formatters.dart';
import 'media_ref.dart';
import 'order.dart';

extension ProofMethodRules on ProofMethod {
  bool get needsOtp => this != ProofMethod.photo;

  bool get needsPhoto => this != ProofMethod.otp;

  String get label => switch (this) {
    ProofMethod.otp => 'OTP',
    ProofMethod.photo => 'Photo',
    ProofMethod.otpAndPhoto => 'OTP and photo',
  };
}

/// Cash collection for a COD drop (plan 3.8.5 and 3.8.6). The rider enters
/// the note value received; anything paid by UPI lowers the cash due.
class CashCheck {
  const CashCheck({
    required this.duePaise,
    required this.receivedPaise,
    this.upiPaise = 0,
  });

  /// Received more than this above the amount due is probably a typo.
  static const int typoMarginPaise = 200000;

  final int duePaise;
  final int receivedPaise;
  final int upiPaise;

  int get cashDuePaise => math.max(0, duePaise - upiPaise);

  int get changePaise => math.max(0, receivedPaise - cashDuePaise);

  int get shortPaise => math.max(0, cashDuePaise - receivedPaise);

  bool get isEnough => shortPaise == 0;

  bool get likelyTypo => receivedPaise - cashDuePaise > typoMarginPaise;

  /// Cash that goes into cash in hand: the amount due, not the note value.
  int get cashCollectedPaise => math.min(receivedPaise, cashDuePaise);

  String? get error => isEnough
      ? null
      : 'Received is ${formatPaise(shortPaise)} short of '
            '${formatPaise(cashDuePaise)}.';
}

/// What the rider still has to do before "Delivered" unlocks.
class DeliveryCheck {
  const DeliveryCheck({
    required this.task,
    this.otpVerified = false,
    this.photo,
    this.cash,
    this.upiPaise = 0,
  });

  final DeliveryTask task;
  final bool otpVerified;
  final MediaRef? photo;
  final CashCheck? cash;
  final int upiPaise;

  int get duePaise => task.payment.amountToCollectPaise;

  bool get paid =>
      duePaise == 0 || upiPaise >= duePaise || (cash?.isEnough ?? false);

  /// Done and missing steps, in the order the screen shows them.
  List<({String label, bool done})> get items => [
    if (task.requiredProof.needsOtp) (label: 'OTP verified', done: otpVerified),
    if (task.requiredProof.needsPhoto)
      (label: 'Delivery photo', done: photo != null),
    if (duePaise > 0) (label: '${formatPaise(duePaise)} collected', done: paid),
  ];

  List<String> get missing => [
    for (final item in items)
      if (!item.done) item.label,
  ];

  bool get isComplete => missing.isEmpty;

  DeliveryProof proof(DateTime at, {int changeFromOwnCashPaise = 0}) {
    final cashPaise = math.max(0, duePaise - upiPaise);
    return DeliveryProof(
      method: task.requiredProof,
      capturedAt: at,
      otpVerified: otpVerified,
      photo: photo,
      cashCollectedPaise: cashPaise,
      upiCollectedPaise: math.min(upiPaise, duePaise),
      changeGivenPaise: changeFromOwnCashPaise,
      collectedVia: duePaise == 0
          ? null
          : upiPaise >= duePaise
          ? CollectionMethod.upiQr
          : upiPaise > 0
          ? CollectionMethod.split
          : CollectionMethod.cash,
    );
  }
}
