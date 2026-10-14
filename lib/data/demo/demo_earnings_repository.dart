import '../../models/money.dart';
import '../repositories/earnings_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

class DemoEarningsRepository implements EarningsRepository {
  DemoEarningsRepository(this._backend);

  final DemoBackend _backend;

  @override
  Future<List<EarningEntry>> entries({
    required DateTime from,
    required DateTime to,
  }) => _backend.engine.run(
    OperationType.loadEarnings,
    () => _backend.db.ledger
        .where((e) => !e.at.isBefore(from) && e.at.isBefore(to))
        .toList(),
  );
}
