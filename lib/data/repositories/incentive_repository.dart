import '../../models/money.dart';

abstract interface class IncentiveRepository {
  /// Current and upcoming incentives with the rider's progress.
  Future<List<Incentive>> incentives();
}
