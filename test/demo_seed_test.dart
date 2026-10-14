import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/data/demo/demo_seed.dart';
import 'package:qwiko_delivery_agent/models/money.dart';
import 'package:qwiko_delivery_agent/models/order.dart';

void main() {
  final now = DateTime(2026, 10, 13, 14);

  test('the same seed builds the same data', () {
    final a = DemoSeed.build(now: now);
    final b = DemoSeed.build(now: now);

    expect(
      a.history.map((t) => t.displayId).toList(),
      b.history.map((t) => t.displayId).toList(),
    );
    expect(
      a.ledger.fold(0, (sum, e) => sum + e.amountPaise),
      b.ledger.fold(0, (sum, e) => sum + e.amountPaise),
    );
  });

  test('a different seed builds different data', () {
    final a = DemoSeed.build(now: now);
    final b = DemoSeed.build(now: now, seed: 7);

    expect(
      a.ledger.fold(0, (sum, e) => sum + e.amountPaise),
      isNot(b.ledger.fold<int>(0, (sum, e) => sum + e.amountPaise)),
    );
  });

  test('history has about 60 days of mostly delivered orders', () {
    final db = DemoSeed.build(now: now);
    final history = db.history;
    expect(history, isNotEmpty);

    final oldest = history.last.lastUpdatedAt;
    expect(now.difference(oldest).inDays, inInclusiveRange(55, 61));

    final delivered = history
        .where((t) => t.status == OrderStatus.delivered)
        .length;
    final ratio = delivered / history.length;
    expect(ratio, inInclusiveRange(0.85, 0.97));
    expect(history.any((t) => t.status == OrderStatus.cancelled), isTrue);
    expect(history.any((t) => t.status == OrderStatus.returned), isTrue);
  });

  test('history is newest first and nothing is in the future', () {
    final history = DemoSeed.build(now: now).history;
    for (var i = 1; i < history.length; i++) {
      expect(
        history[i - 1].lastUpdatedAt.isBefore(history[i].lastUpdatedAt),
        isFalse,
      );
    }
    expect(history.first.lastUpdatedAt.isAfter(now), isFalse);
  });

  test('every delivered order is paid in the ledger', () {
    final db = DemoSeed.build(now: now);
    final paidOrders = db.ledger
        .where((e) => e.type == EarningType.orderPay)
        .map((e) => e.orderId)
        .toSet();
    for (final task in db.history.where(
      (t) => t.status == OrderStatus.delivered,
    )) {
      expect(paidOrders, contains(task.orderId));
    }
  });

  test('cash in hand stays under the limit', () {
    final cash = DemoSeed.build(now: now).cash;
    expect(cash.balancePaise, greaterThanOrEqualTo(0));
    expect(cash.balancePaise, lessThanOrEqualTo(cash.limitPaise));
  });
}
