import '../core/clock.dart';
import '../core/domain_events.dart';
import '../data/repositories/incentive_repository.dart';
import '../models/money.dart';
import 'loadable_controller.dart';

/// Incentives and progress. Phase 11 adds the full Incentives screen; the
/// dashboard uses [todayMilestone].
class IncentivesController extends LoadableController {
  IncentivesController({
    required this._repository,
    required this._clock,
    super.events,
  });

  final IncentiveRepository _repository;
  final Clock _clock;

  List<Incentive> _incentives = const [];

  List<Incentive> get incentives => _incentives;

  /// The active incentive ending today that needs the fewest orders to reach
  /// its next reward.
  Incentive? get todayMilestone {
    final now = _clock.now();
    final tomorrow = startOfDay(now).add(const Duration(days: 1));
    Incentive? best;
    for (final incentive in _incentives) {
      final next = incentive.nextTier;
      if (incentive.status != IncentiveStatus.active ||
          next == null ||
          now.isBefore(incentive.windowStart) ||
          incentive.windowEnd.isAfter(tomorrow)) {
        continue;
      }
      if (best == null ||
          next.target - incentive.progress <
              best.nextTier!.target - best.progress) {
        best = incentive;
      }
    }
    return best;
  }

  /// Orders left for the next reward of [todayMilestone], if it is close
  /// enough that going offline puts it at risk.
  ({int orders, int rewardPaise})? get rewardAtRisk {
    final incentive = todayMilestone;
    final next = incentive?.nextTier;
    if (incentive == null || next == null) return null;
    final left = next.target - incentive.progress;
    return left <= 3 ? (orders: left, rewardPaise: next.rewardPaise) : null;
  }

  @override
  Future<void> fetch() async => _incentives = await _repository.incentives();

  @override
  void clearData() => _incentives = const [];

  @override
  bool shouldRefresh(DomainEvent event) =>
      event is LedgerChanged ||
      event is OrderCompleted ||
      event is IncentivesChanged;
}
