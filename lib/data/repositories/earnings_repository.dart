import '../../models/money.dart';

abstract interface class EarningsRepository {
  /// Ledger entries credited in `[from, to)`, newest first.
  Future<List<EarningEntry>> entries({
    required DateTime from,
    required DateTime to,
  });
}
