import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_routes.dart';
import 'package:qwiko_delivery_agent/app/app_scope.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/app/app_theme.dart';
import 'package:qwiko_delivery_agent/controllers/history_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/models/support.dart';
import 'package:qwiko_delivery_agent/screens/orders/order_details_screen.dart';
import 'package:qwiko_delivery_agent/screens/orders/order_history_view.dart';

void main() {
  final now = DateTime(2026, 10, 13, 14);

  AppServices build() => AppServices.demo(
    clock: FakeClock(now),
    latency: Duration.zero,
    firstOfferDelay: const Duration(minutes: 30),
    offerInterval: const Duration(minutes: 30),
  );

  Future<AppServices> signedIn() async {
    final services = build();
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    return services;
  }

  Future<List<DeliveryTask>> loadAll(HistoryController history) async {
    while (history.hasMore) {
      await history.loadMore();
    }
    return history.items;
  }

  group('History filters', () {
    late AppServices services;
    late HistoryController history;

    setUp(() async {
      services = await signedIn();
      history = services.history;
      await history.load();
    });

    tearDown(() => services.dispose());

    test('status, period and search combine, then clear', () async {
      await history.setFilter(HistoryFilter.delivered);
      await history.setPeriod(HistoryPeriod.thisWeek);
      final week = await loadAll(history);
      expect(week, isNotEmpty);
      final weekStart = startOfDay(now)
          .subtract(Duration(days: now.weekday - 1));
      for (final order in week) {
        expect(order.status, OrderStatus.delivered);
        expect(order.endedAt.isBefore(weekStart), isFalse);
      }

      final target = week.last;
      await history.setSearch(target.displayId);
      expect(history.items.map((o) => o.orderId), [target.orderId]);
      expect(history.hasFilters, isTrue);

      await history.clearFilters();
      expect(history.hasFilters, isFalse);
      expect(history.period, HistoryPeriod.all);
      expect(history.items.length, history.pageSize);
    });

    test('filters survive leaving and reopening the tab', () async {
      await history.setFilter(HistoryFilter.cancelled);
      await history.setPeriod(HistoryPeriod.thisMonth);
      await history.refresh();
      expect(history.filter, HistoryFilter.cancelled);
      expect(history.period, HistoryPeriod.thisMonth);
      expect(
        history.items.every((o) => o.status == OrderStatus.cancelled),
        isTrue,
      );
    });

    test('daily totals match the orders listed', () async {
      await history.setPeriod(HistoryPeriod.thisMonth);
      final orders = await loadAll(history);
      final byDay = <DateTime, int>{};
      for (final order in orders) {
        final day = startOfDay(order.endedAt);
        byDay[day] = (byDay[day] ?? 0) + order.earnedPaise;
      }
      final summary = history.filteredSummary!;
      expect(
        summary.byDay.map((day, t) => MapEntry(day, t.earnedPaise)),
        byDay,
      );
      expect(summary.orderCount, orders.length);
      expect(
        summary.earnedPaise,
        orders.fold(0, (sum, o) => sum + o.earnedPaise),
      );
    });

    test('a custom range includes both end days', () async {
      await history.setPeriod(HistoryPeriod.yesterday);
      final yesterday = await loadAll(history);
      final day = startOfDay(now).subtract(const Duration(days: 1));
      await history.setPeriod(
        HistoryPeriod.custom,
        range: (from: day, to: day),
      );
      final custom = await loadAll(history);
      expect(custom.map((o) => o.orderId), yesterday.map((o) => o.orderId));
    });

    test('custom period without a range is ignored', () async {
      await history.setPeriod(HistoryPeriod.custom);
      expect(history.period, HistoryPeriod.all);
    });

    test('pages hold 20 orders', () async {
      expect(history.items.length, 20);
      expect(history.hasMore, isTrue);
      await history.loadMore();
      expect(history.items.length, 40);
    });

    test('completion and on-time rates cover the last 7 days', () {
      final week = history.lastWeek!;
      expect(week.orderCount, greaterThan(0));
      expect(week.completionPercent, inInclusiveRange(0, 100));
      expect(week.onTimePercent, inInclusiveRange(0, 100));
      expect(week.onTimeCount, lessThanOrEqualTo(week.deliveredCount));
    });
  });

  group('History screens', () {
    late AppServices services;

    void testScreen(String description, WidgetTesterCallback body) {
      testWidgets(description, (tester) async {
        tester.view.physicalSize = const Size(400, 860) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        services = build();
        await services.session.signInWithEmail(
          email: 'arjun@example.com',
          password: 'password123',
        );
        await body(tester);
        await tester.pumpWidget(const SizedBox());
        services.dispose();
        await tester.pump(const Duration(seconds: 11));
      });
    }

    Future<void> pumpApp(WidgetTester tester, Widget home) async {
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: home,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testScreen('a search with no match offers to clear filters', (
      tester,
    ) async {
      await pumpApp(tester, const Scaffold(body: OrderHistoryView()));
      expect(find.text('Search by order ID'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ZZZ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('No orders match "ZZZ"'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(services.history.hasFilters, isFalse);
      expect(find.text('No orders match "ZZZ"'), findsNothing);
    });

    testScreen('a finished order shows the first name and reports issues', (
      tester,
    ) async {
      await services.history.load();
      final order = services.history.items.firstWhere(
        (o) => o.status == OrderStatus.delivered,
      );
      await pumpApp(tester, OrderDetailsScreen(orderId: order.orderId));

      expect(find.text(order.customer.firstName), findsOneWidget);
      expect(find.text(order.customer.fullName), findsNothing);
      expect(find.text(order.customer.fullAddress), findsNothing);

      final report = find.text('Report an issue with this order');
      await tester.scrollUntilVisible(
        report,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(report);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay missing'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'What happened?'),
        'Delivery fee did not show up in earnings.',
      );
      await tester.tap(find.text('Send to support'));
      await tester.pumpAndSettle();

      final ticket = services.support.tickets.first;
      expect(ticket.orderId, order.orderId);
      expect(ticket.source, TicketSource.order);
      expect(ticket.category, 'Pay missing');
      expect(find.text('Request ${ticket.id} sent to support'), findsOneWidget);
      expect(find.text('Support requests'), findsOneWidget);
    });
  });
}
