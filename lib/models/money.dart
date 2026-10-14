import 'dart:math';

enum EarningType {
  orderPay('Order pay'),
  waitingPay('Waiting pay'),
  surge('Surge'),
  batchBonus('Batch bonus'),
  compensation('Compensation'),
  tip('Customer tip'),
  incentive('Incentive'),
  adjustment('Adjustment'),
  payout('Payout');

  const EarningType(this.label);

  final String label;
}

/// One line in the earnings ledger, the single source of truth for money
/// earned. Summaries are always computed from these.
class EarningEntry {
  const EarningEntry({
    required this.id,
    required this.type,
    required this.amountPaise,
    required this.at,
    required this.label,
    this.orderId,
  });

  final String id;
  final EarningType type;

  /// Positive for credits; payouts are negative.
  final int amountPaise;

  /// When it was credited; this decides which day it belongs to.
  final DateTime at;
  final String label;
  final String? orderId;

  @override
  bool operator ==(Object other) => other is EarningEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'EarningEntry(${type.name}, $amountPaise, $at)';
}

enum IncentiveType { dailyMilestone, peakHours, weeklyTarget, rainBonus }

enum IncentiveStatus { upcoming, active, achieved, missed }

class IncentiveTier {
  const IncentiveTier({required this.target, required this.rewardPaise});

  final int target;
  final int rewardPaise;
}

class Incentive {
  const Incentive({
    required this.id,
    required this.type,
    required this.title,
    required this.tiers,
    required this.windowStart,
    required this.windowEnd,
    this.progress = 0,
    this.status = IncentiveStatus.upcoming,
    this.terms = '',
  });

  final String id;
  final IncentiveType type;
  final String title;
  final List<IncentiveTier> tiers;
  final int progress;
  final DateTime windowStart;
  final DateTime windowEnd;
  final IncentiveStatus status;
  final String terms;

  /// Peak-hour and rain bonuses pay the first tier's reward for every
  /// order in the window instead of unlocking tiers.
  bool get isPerOrder =>
      type == IncentiveType.peakHours || type == IncentiveType.rainBonus;

  IncentiveTier? get nextTier {
    if (isPerOrder) return null;
    for (final tier in tiers) {
      if (progress < tier.target) return tier;
    }
    return null;
  }

  /// Total credited so far.
  int get earnedPaise {
    if (isPerOrder) {
      return tiers.isEmpty ? 0 : progress * tiers.first.rewardPaise;
    }
    var reward = 0;
    for (final tier in tiers) {
      if (progress >= tier.target) reward = tier.rewardPaise;
    }
    return reward;
  }

  /// Where the incentive stands at [now].
  IncentiveStatus statusAt(DateTime now) {
    if (now.isBefore(windowStart)) return IncentiveStatus.upcoming;
    final reachedFirst = isPerOrder
        ? progress > 0
        : tiers.isNotEmpty && progress >= tiers.first.target;
    if (!isPerOrder && tiers.isNotEmpty && progress >= tiers.last.target) {
      return IncentiveStatus.achieved;
    }
    if (now.isBefore(windowEnd)) return IncentiveStatus.active;
    return reachedFirst ? IncentiveStatus.achieved : IncentiveStatus.missed;
  }

  Incentive copyWith({
    int? progress,
    IncentiveStatus? status,
    DateTime? windowStart,
    DateTime? windowEnd,
  }) => Incentive(
    id: id,
    type: type,
    title: title,
    tiers: tiers,
    windowStart: windowStart ?? this.windowStart,
    windowEnd: windowEnd ?? this.windowEnd,
    progress: progress ?? this.progress,
    status: status ?? this.status,
    terms: terms,
  );

  @override
  bool operator ==(Object other) =>
      other is Incentive &&
      other.id == id &&
      other.progress == progress &&
      other.status == status &&
      other.windowEnd == windowEnd;

  @override
  int get hashCode => Object.hash(id, progress, status, windowEnd);
}

enum CashMovementType { codCollected, changeGiven, deposit }

class CashMovement {
  const CashMovement({
    required this.type,
    required this.amountPaise,
    required this.at,
    this.orderId,
  });

  final CashMovementType type;

  /// Always positive; [type] decides the direction.
  final int amountPaise;
  final DateTime at;
  final String? orderId;

  int get signedPaise =>
      type == CashMovementType.codCollected ? amountPaise : -amountPaise;
}

enum DepositMethod { storeCounter, upi }

class CashDeposit {
  const CashDeposit({
    required this.id,
    required this.amountPaise,
    required this.at,
    required this.method,
    required this.reference,
  });

  final String id;
  final int amountPaise;
  final DateTime at;
  final DepositMethod method;
  final String reference;
}

class CashInHand {
  const CashInHand({
    this.limitPaise = 200000,
    this.movements = const [],
    this.deposits = const [],
  });

  final int limitPaise;
  final List<CashMovement> movements;
  final List<CashDeposit> deposits;

  int get balancePaise => movements.fold(0, (sum, m) => sum + m.signedPaise);

  double get usage => limitPaise == 0 ? 0 : balancePaise / limitPaise;

  /// COD cash that can still be collected before reaching the limit.
  int get roomPaise => max(0, limitPaise - balancePaise);

  /// Whether collecting [paise] more keeps cash in hand within the limit.
  bool canCollect(int paise) => balancePaise + paise <= limitPaise;

  CashInHand copyWith({
    List<CashMovement>? movements,
    List<CashDeposit>? deposits,
  }) => CashInHand(
    limitPaise: limitPaise,
    movements: movements ?? this.movements,
    deposits: deposits ?? this.deposits,
  );
}

class WalletBalance {
  const WalletBalance({
    required this.withdrawablePaise,
    required this.nextScheduledPayoutOn,
    this.pendingPaise = 0,
  });

  final int withdrawablePaise;
  final int pendingPaise;
  final DateTime nextScheduledPayoutOn;
}

enum PayoutStatus {
  requested('Requested'),
  processing('Processing'),
  paid('Sent to bank'),
  failed('Failed');

  const PayoutStatus(this.label);

  final String label;

  bool get isInFlight => this == requested || this == processing;
}

class Payout {
  const Payout({
    required this.id,
    required this.amountPaise,
    required this.requestedAt,
    required this.status,
    required this.reference,
    this.failureReason,
    this.isInstant = false,
    this.isScheduled = false,
    this.feePaise = 0,
  });

  final String id;
  final int amountPaise;
  final DateTime requestedAt;
  final PayoutStatus status;
  final String reference;
  final String? failureReason;
  final bool isInstant;
  final bool isScheduled;
  final int feePaise;

  String get kind => isInstant
      ? 'Instant'
      : isScheduled
      ? 'Weekly'
      : 'Payout';

  Payout copyWith({PayoutStatus? status, String? failureReason}) => Payout(
    id: id,
    amountPaise: amountPaise,
    requestedAt: requestedAt,
    status: status ?? this.status,
    reference: reference,
    failureReason: failureReason ?? this.failureReason,
    isInstant: isInstant,
    isScheduled: isScheduled,
    feePaise: feePaise,
  );

  @override
  bool operator ==(Object other) =>
      other is Payout && other.id == id && other.status == status;

  @override
  int get hashCode => Object.hash(id, status);

  @override
  String toString() => 'Payout($id, $amountPaise, ${status.name})';
}
