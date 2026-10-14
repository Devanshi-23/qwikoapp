enum ActivityType {
  wentOnline('Went online'),
  wentOffline('Went offline'),
  breakStarted('Break started'),
  breakEnded('Break ended'),
  offerAccepted('Offer accepted'),
  offerDeclined('Offer declined'),
  offerMissed('Offer missed'),
  offerWithdrawn('Offer taken by another partner'),
  delivered('Delivered'),
  cancelled('Order cancelled'),
  payoutRequested('Payout requested'),
  cashDeposited('Cash deposited'),
  sos('SOS');

  const ActivityType(this.label);

  final String label;

  bool get isSession =>
      this == wentOnline ||
      this == wentOffline ||
      this == breakStarted ||
      this == breakEnded;

  /// Counts towards the acceptance rate.
  bool get isOfferDecision =>
      this == offerAccepted || this == offerDeclined || this == offerMissed;

  /// Any offer event, including offers withdrawn before the rider answered.
  bool get isOffer => isOfferDecision || this == offerWithdrawn;
}

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.type,
    required this.at,
    this.details = '',
  });

  final String id;
  final ActivityType type;
  final DateTime at;
  final String details;

  @override
  bool operator ==(Object other) => other is ActivityEvent && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ActivityEvent(${type.name} at $at)';
}

/// Offer decisions over a period. Acceptance rate = accepted / (accepted +
/// declined + missed).
class AcceptanceStats {
  const AcceptanceStats({
    this.accepted = 0,
    this.declined = 0,
    this.missed = 0,
  });

  factory AcceptanceStats.from(Iterable<ActivityEvent> events) {
    var accepted = 0, declined = 0, missed = 0;
    for (final event in events) {
      switch (event.type) {
        case ActivityType.offerAccepted:
          accepted++;
        case ActivityType.offerDeclined:
          declined++;
        case ActivityType.offerMissed:
          missed++;
        default:
          break;
      }
    }
    return AcceptanceStats(
      accepted: accepted,
      declined: declined,
      missed: missed,
    );
  }

  final int accepted;
  final int declined;
  final int missed;

  int get offered => accepted + declined + missed;

  /// Null when no offers were received.
  double? get rate => offered == 0 ? null : accepted / offered;

  /// Whole percent, for display.
  int? get percent {
    final rate = this.rate;
    return rate == null ? null : (rate * 100).round();
  }
}
