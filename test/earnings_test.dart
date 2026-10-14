import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_scope.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/app/app_theme.dart';
import 'package:qwiko_delivery_agent/controllers/earnings_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/money.dart';
import 'package:qwiko_delivery_agent/models/notification.dart';
import 'package:qwiko_delivery_agent/models/partner.dart';
import 'package:qwiko_delivery_agent/screens/earnings/earnings_view.dart';
import 'package:qwiko_delivery_agent/screens/wallet/withdraw_sheet.dart';

void main() {
  late AppServices services;
  late FakeClock clock;

  setUp(() async {
    services = AppServices.demo(
      clock: clock = FakeClock(DateTime(2026, 10, 13, 14)),
      latency: Duration.zero,
      firstOfferDelay: const Duration(minutes: 30),
      offerInterval: const Duration(minutes: 30),
    );
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
  });

  tearDown(() => services.dispose());

  group('Earnings periods', () {
    late EarningsController earnings;

    setUp(() async {
      earnings = services.earnings;
      await earnings.load();
    });

    int sum(List<EarningEntry> entries) =>
        entries.fold(0, (total, e) => total + e.amountPaise);

    test('totals, bars, breakdown and orders agree for every period', () async {
      for (final period in EarningsPeriod.values) {
        await earnings.setPeriod(period);
        for (var back = 0; back < 3; back++) {
          final total = earnings.totalPaise;
          expect(total, sum(earnings.entries));
          expect(earnings.buckets.fold(0, (s, b) => s + b.totalPaise), total);
          expect(earnings.breakdown.fold(0, (s, b) => s + b.$2), total);
          for (final entry in earnings.entries) {
            expect(entry.at.isBefore(earnings.range.from), isFalse);
            expect(entry.at.isBefore(earnings.range.to), isTrue);
          }
          await earnings.previous();
        }
      }
    });

    test('a week equals the sum of its seven days', () async {
      await earnings.setPeriod(EarningsPeriod.week);
      await earnings.previous();
      final week = earnings.totalPaise;
      final weekStart = earnings.range.from;

      await earnings.setPeriod(EarningsPeriod.day);
      final today = startOfDay(clock.now());
      while (earnings.range.from != weekStart.add(const Duration(days: 6))) {
        await earnings.previous();
      }
      var days = 0;
      for (var i = 0; i < 7; i++) {
        days += earnings.totalPaise;
        await earnings.previous();
      }
      expect(days, week);
      expect(week, greaterThan(0));
      expect(today.weekday, DateTime.tuesday);
    });

    test('labels and paging limits', () async {
      await earnings.setPeriod(EarningsPeriod.day);
      expect(earnings.rangeLabel, 'Today');
      expect(earnings.canGoNext, isFalse);
      await earnings.previous();
      expect(earnings.rangeLabel, 'Yesterday');
      expect(earnings.canGoNext, isTrue);

      await earnings.setPeriod(EarningsPeriod.month);
      expect(earnings.rangeLabel, 'October 2026');
      expect(earnings.buckets, hasLength(31));
      for (var i = 0; i < 10 && earnings.canGoPrevious; i++) {
        await earnings.previous();
      }
      expect(earnings.canGoPrevious, isFalse);
    });

    test('per-order totals match the order details', () async {
      await earnings.setPeriod(EarningsPeriod.week);
      final order = earnings.orders.first;
      final details = await services.history.orderById(order.orderId);
      expect(order.totalPaise, details.earnedPaise);
    });
  });

  group('Withdrawals', () {
    setUp(() async {
      await services.profile.load();
      await services.wallet.load();
    });

    Future<String> failure(Future<void> Function() action) async {
      try {
        await action();
      } on AppFailure catch (f) {
        return f.message;
      }
      fail('Expected a failure');
    }

    test('validation covers every rule', () async {
      final wallet = services.wallet;
      final available = wallet.balance!.withdrawablePaise;
      expect(available, greaterThan(10000));

      expect(
        await failure(() => wallet.withdraw(5000)),
        'Minimum withdrawal is ₹100',
      );
      expect(
        await failure(() => wallet.withdraw(available + 100)),
        startsWith('You can withdraw up to'),
      );

      services.demo!.failNext(OperationType.withdraw);
      await failure(() => wallet.withdraw(10000));
      expect(
        wallet.payouts.where(
          (p) => p.isInstant && p.requestedAt == clock.now(),
        ),
        isEmpty,
      );

      await wallet.withdraw(10000);
      await wallet.refresh();
      expect(wallet.alreadyWithdrewToday, isTrue);
      expect(
        await failure(() => wallet.withdraw(10000)),
        'You can make one instant withdrawal per day',
      );
    });

    test('zero balance and an unverified bank block withdrawing', () async {
      final wallet = services.wallet;
      expect(services.demo!.runWeeklyPayout(), isNotNull);
      await wallet.refresh();
      expect(wallet.balance!.withdrawablePaise, 0);
      expect(
        await failure(() => wallet.withdraw(10000)),
        'No balance available to withdraw',
      );
      expect(
        withdrawBlocker(
          bank: services.profile.profile!.bank,
          availablePaise: 0,
          alreadyWithdrewToday: false,
        ),
        startsWith('You need at least ₹100'),
      );

      final bank = services.profile.profile!.bank!;
      await services.profile.updateBank(
        BankAccount(
          holderName: bank.holderName,
          accountNumber: bank.accountNumber,
          ifsc: bank.ifsc,
          bankName: bank.bankName,
          verification: BankVerification.verifying,
        ),
        upiId: 'arjun@upi',
      );
      expect(
        await failure(() => wallet.withdraw(10000)),
        'Your bank account is still being verified.',
      );
    });

    test('a payout moves requested → processing → paid on the clock', () async {
      final wallet = services.wallet;
      final before = wallet.balance!.withdrawablePaise;
      final payout = await wallet.withdraw(20000);
      expect(payout.status, PayoutStatus.requested);
      await wallet.refresh();
      expect(wallet.balance!.withdrawablePaise, before - 20000);
      expect(wallet.balance!.pendingPaise, 20000);

      clock.advance(const Duration(seconds: 6));
      await wallet.refresh();
      expect(wallet.payouts.first.status, PayoutStatus.processing);

      clock.advance(const Duration(seconds: 15));
      await wallet.refresh();
      expect(wallet.payouts.first.status, PayoutStatus.paid);
      await services.notifications.load();
      expect(
        services.notifications.items.first.title,
        '₹200 sent to your bank',
      );
    });

    test('an injected bank failure returns the money', () async {
      final wallet = services.wallet;
      final before = wallet.balance!.withdrawablePaise;
      services.demo!.payoutFails = true;
      await wallet.withdraw(20000);
      clock.advance(const Duration(seconds: 21));
      await wallet.refresh();
      final failed = wallet.payouts.first;
      expect(failed.status, PayoutStatus.failed);
      expect(failed.failureReason, contains('declined'));
      expect(wallet.balance!.withdrawablePaise, before);
      expect(wallet.alreadyWithdrewToday, isFalse);
      await services.notifications.load();
      expect(
        services.notifications.items.first.category,
        NotificationCategory.earnings,
      );
    });

    test('the weekly payout pays the whole balance', () async {
      final wallet = services.wallet;
      final before = wallet.balance!.withdrawablePaise;
      final payout = services.demo!.runWeeklyPayout()!;
      expect(payout.isScheduled, isTrue);
      expect(payout.amountPaise, before);
      expect(services.demo!.runWeeklyPayout(), isNull);
    });
  });

  group('Cash limit', () {
    test('over the limit blocks going online; depositing clears it', () async {
      await services.wallet.load();
      final limit = services.wallet.cash.limitPaise;
      services.demo!.setCashInHand(limit);
      await services.wallet.refresh();
      await expectLater(
        services.availability.goOnline(),
        throwsA(isA<NotAllowedFailure>()),
      );

      await services.wallet.depositCash(limit, DepositMethod.upi);
      await services.wallet.refresh();
      expect(services.wallet.cash.balancePaise, 0);
      expect(services.wallet.cash.deposits.last.reference, startsWith('DEP'));
      await services.availability.goOnline();
      expect(services.availability.isOnline, isTrue);
      await services.availability.goOffline();
    });
  });

  group('Incentives', () {
    test('status follows the clock', () {
      final today = DateTime(2026, 10, 13);
      final daily = Incentive(
        id: 'd',
        type: IncentiveType.dailyMilestone,
        title: 'Daily',
        tiers: const [
          IncentiveTier(target: 2, rewardPaise: 100),
          IncentiveTier(target: 4, rewardPaise: 300),
        ],
        windowStart: today.add(const Duration(hours: 8)),
        windowEnd: today.add(const Duration(hours: 20)),
      );
      expect(daily.statusAt(today), IncentiveStatus.upcoming);
      expect(
        daily.statusAt(today.add(const Duration(hours: 9))),
        IncentiveStatus.active,
      );
      expect(
        daily.statusAt(today.add(const Duration(hours: 21))),
        IncentiveStatus.missed,
      );
      expect(
        daily
            .copyWith(progress: 2)
            .statusAt(today.add(const Duration(hours: 21))),
        IncentiveStatus.achieved,
      );
      expect(
        daily
            .copyWith(progress: 4)
            .statusAt(today.add(const Duration(hours: 9))),
        IncentiveStatus.achieved,
      );
      expect(daily.copyWith(progress: 3).earnedPaise, 100);
    });

    test('rain starts and ends a per-order rain bonus', () async {
      final incentives = services.incentives;
      await incentives.load();
      final demo = services.demo!;
      demo.raining = true;
      await incentives.refresh();
      final rain = incentives.incentives.firstWhere(
        (i) => i.type == IncentiveType.rainBonus,
      );
      expect(rain.status, IncentiveStatus.active);
      expect(rain.isPerOrder, isTrue);

      demo.raining = false;
      await incentives.refresh();
      expect(
        incentives.incentives
            .firstWhere((i) => i.type == IncentiveType.rainBonus)
            .status,
        IncentiveStatus.missed,
      );
    });

    test('lunch peak is active at 2 PM with today\'s orders counted', () async {
      await services.incentives.load();
      final lunch = services.incentives.incentives.firstWhere(
        (i) => i.id == 'inc-lunch',
      );
      expect(lunch.status, IncentiveStatus.active);
      expect(
        services.incentives.incentives
            .firstWhere((i) => i.id == 'inc-peak')
            .status,
        IncentiveStatus.upcoming,
      );
    });
  });

  testWidgets('Earnings tab pages periods and opens a withdraw sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await services.profile.load();
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: EarningsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This week'), findsWidgets);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsWidgets);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsWidgets);

    await tester.tap(find.text('Withdraw now'));
    await tester.pumpAndSettle();
    expect(find.text('Fee'), findsOneWidget);
    expect(find.textContaining('one per day'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
