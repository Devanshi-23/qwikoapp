import '../../core/clock.dart';
import '../../core/failures.dart';
import '../../models/order.dart';
import '../repositories/history_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

class DemoHistoryRepository implements HistoryRepository {
  DemoHistoryRepository(this._backend);

  final DemoBackend _backend;

  Iterable<DeliveryTask> _matching(HistoryQuery query) {
    final search = query.search.trim().toUpperCase().replaceAll('#', '');
    return _backend.db.history.where((task) {
      if (query.statuses != null && !query.statuses!.contains(task.status)) {
        return false;
      }
      final at = task.endedAt;
      if (query.from != null && at.isBefore(query.from!)) return false;
      if (query.to != null && !at.isBefore(query.to!)) return false;
      return search.isEmpty || task.displayId.toUpperCase().contains(search);
    });
  }

  @override
  Future<HistoryPage> fetchPage(
    HistoryQuery query, {
    required int page,
    int pageSize = 20,
  }) => _backend.engine.run(OperationType.loadHistory, () {
    final all = _matching(query).toList();
    final start = page * pageSize;
    final items = all.skip(start).take(pageSize).toList();
    return HistoryPage(
      items: items,
      hasMore: start + items.length < all.length,
    );
  });

  @override
  Future<HistorySummary> summary(HistoryQuery query) =>
      _backend.engine.run(OperationType.loadHistory, () {
        final matching = _matching(query).toList();
        final delivered = matching.where(
          (t) => t.status == OrderStatus.delivered,
        );
        final byDay = <DateTime, ({int orders, int earnedPaise})>{};
        for (final task in matching) {
          final day = startOfDay(task.endedAt);
          final total = byDay[day] ?? (orders: 0, earnedPaise: 0);
          byDay[day] = (
            orders: total.orders + 1,
            earnedPaise: total.earnedPaise + task.earnedPaise,
          );
        }
        return HistorySummary(
          deliveredCount: delivered.length,
          earnedPaise: matching.fold(0, (sum, t) => sum + t.earnedPaise),
          distanceM: delivered.fold(0, (sum, t) => sum + t.distanceM),
          orderCount: matching.length,
          onTimeCount: delivered
              .where((t) => !t.endedAt.isAfter(t.promisedBy))
              .length,
          byDay: byDay,
        );
      });

  @override
  Future<DeliveryTask> fetchOrder(String orderId) =>
      _backend.engine.run(OperationType.loadHistory, () {
        final candidates = [
          ..._backend.db.history,
          ...?_backend.db.activeTrip?.tasks,
        ];
        for (final task in candidates) {
          if (task.orderId == orderId) return task;
        }
        throw const NotFoundFailure("We couldn't find this order.");
      });
}
