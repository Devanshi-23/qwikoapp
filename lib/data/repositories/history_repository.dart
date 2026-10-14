import '../../models/order.dart';

class HistoryQuery {
  const HistoryQuery({this.statuses, this.from, this.to, this.search = ''});

  /// `null` means all end states.
  final Set<OrderStatus>? statuses;
  final DateTime? from;
  final DateTime? to;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is HistoryQuery &&
      _sameSet(other.statuses, statuses) &&
      other.from == from &&
      other.to == to &&
      other.search == search;

  @override
  int get hashCode => Object.hash(
    statuses == null ? null : Object.hashAllUnordered(statuses!),
    from,
    to,
    search,
  );
}

bool _sameSet(Set<OrderStatus>? a, Set<OrderStatus>? b) {
  if (a == null || b == null) return a == b;
  return a.length == b.length && a.containsAll(b);
}

class HistoryPage {
  const HistoryPage({required this.items, required this.hasMore});

  final List<DeliveryTask> items;
  final bool hasMore;
}

class HistorySummary {
  const HistorySummary({
    required this.deliveredCount,
    required this.earnedPaise,
    required this.distanceM,
    this.orderCount = 0,
    this.onTimeCount = 0,
    this.byDay = const {},
  });

  final int deliveredCount;
  final int earnedPaise;
  final int distanceM;

  /// Every matching order, whatever its outcome.
  final int orderCount;

  /// Delivered orders that reached the customer by the promised time.
  final int onTimeCount;

  /// Delivered share of all orders, or null with no orders.
  int? get completionPercent =>
      orderCount == 0 ? null : (deliveredCount * 100 / orderCount).round();

  /// On-time share of delivered orders, or null with none delivered.
  int? get onTimePercent =>
      deliveredCount == 0 ? null : (onTimeCount * 100 / deliveredCount).round();

  /// Orders and earnings per day (keyed by the start of the day).
  final Map<DateTime, ({int orders, int earnedPaise})> byDay;
}

abstract interface class HistoryRepository {
  /// Newest first, in pages of [pageSize].
  Future<HistoryPage> fetchPage(
    HistoryQuery query, {
    required int page,
    int pageSize = 20,
  });

  Future<HistorySummary> summary(HistoryQuery query);

  Future<DeliveryTask> fetchOrder(String orderId);
}
