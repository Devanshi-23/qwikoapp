import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/controllers/active_trip_controller.dart';
import 'package:qwiko_delivery_agent/controllers/navigation_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/money.dart';
import 'package:qwiko_delivery_agent/models/media_ref.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/models/store_issue.dart';
import 'package:qwiko_delivery_agent/models/trip.dart';
import 'package:qwiko_delivery_agent/services/location/simulated_location_source.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await settle();
  }
  expect(condition(), isTrue, reason: 'condition not met in time');
}

Matcher failsWith(String text) => throwsA(
  isA<AppFailure>().having((f) => f.message, 'message', contains(text)),
);

void main() {
  late FakeClock clock;
  late AppServices services;

  setUp(() {
    services = AppServices.demo(
      clock: clock = FakeClock(DateTime(2026, 10, 13, 14)),
      latency: Duration.zero,
      firstOfferDelay: const Duration(minutes: 30),
      offerInterval: const Duration(minutes: 30),
    );
  });

  tearDown(() => services.dispose());

  ActiveTripController trip() => services.trip;
  DeliveryTrip current() => services.trip.trip!;

  Future<DeliveryTrip> acceptOrder({
    bool batched = false,
    PaymentMode payment = PaymentMode.prepaid,
  }) async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.wallet.load();
    await services.availability.goOnline();
    expect(
      services.demo!.sendOffer(
        OfferRequest(batched: batched, payment: payment),
      ),
      isTrue,
    );
    await waitFor(() => services.offers.offer != null);
    final accepted = await services.offers.accept();
    await waitFor(
      () =>
          services.navigation.status == RouteStatus.ready &&
          !services.navigation.isPlanning,
    );
    return accepted;
  }

  Future<void> arrive() async {
    services.demo!.jumpToNextStop();
    await trip().arrivedAtStore();
  }

  StoreIssueRequest itemIssue(
    DeliveryTask task,
    List<int> indexes,
    ItemResolution resolution,
  ) => StoreIssueRequest(
    type: IssueType.itemMissing,
    items: [for (final i in indexes) (orderId: task.orderId, index: i)],
    resolution: resolution,
  );

  group('Arriving at the store', () {
    test('is refused outside 200 m and says how far the store is', () async {
      await acceptOrder();
      expect(trip().distanceToStoreM, greaterThan(200));
      expect(trip().isNearStore, isFalse);

      await expectLater(trip().arrivedAtStore(), failsWith('within 200 m'));
      expect(current().status, TripStatus.headingToStore);
    });

    test('works within the geofence and records the event', () async {
      await acceptOrder();
      services.demo!.jumpToNextStop();
      expect(trip().isNearStore, isTrue);

      await trip().arrivedAtStore();

      expect(current().status, TripStatus.atStore);
      expect(current().waitStartedAt, clock.now());
      for (final task in current().tasks) {
        expect(task.status, OrderStatus.arrivedAtStore);
        expect(task.timeOf(OrderEventType.arrivedAtStore), clock.now());
      }
    });

    test('needs location to confirm arrival', () async {
      await acceptOrder();
      services.demo!.jumpToNextStop();
      services.demo!.locationServiceEnabled = false;

      expect(trip().distanceToStoreM, isNull);
      await expectLater(trip().arrivedAtStore(), failsWith('Turn on location'));
    });
  });

  group('Pickup checklist', () {
    test('pickup is refused until every item is checked', () async {
      await acceptOrder();
      await arrive();
      final items = current().pickupItems.length;
      expect(items, greaterThan(0));
      expect(current().uncheckedCount, items);

      await expectLater(trip().pickedUp(), failsWith('Check $items more'));

      final task = current().tasks.first;
      await trip().setItemChecked((
        orderId: task.orderId,
        index: 0,
      ), checked: true);
      expect(current().uncheckedCount, items - 1);

      await trip().checkAllItems();
      expect(current().pickupBlockedReason(clock.now()), isNull);
      await trip().pickedUp();

      expect(current().status, TripStatus.inProgress);
      expect(current().currentTask.status, OrderStatus.headingToCustomer);
      expect(
        current().tasks.first.timeOf(OrderEventType.pickedUp),
        clock.now(),
      );
    });

    test('pharmacy and cold-chain tags add handling checks', () async {
      final accepted = await acceptOrder();
      await arrive();
      final tagged = DeliveryTrip(
        id: accepted.id,
        offerId: accepted.offerId,
        store: accepted.store,
        tasks: current().tasks,
        acceptedAt: accepted.acceptedAt,
        startPosition: accepted.startPosition,
        status: TripStatus.atStore,
        tags: const {OfferTag.pharmacy, OfferTag.heavy},
      );
      expect(tagged.pickupChecks, [OfferTag.pharmacy]);
      expect(tagged.uncheckedCount, tagged.pickupItems.length + 1);
      expect(
        tagged.copyWith(checkedTags: {OfferTag.pharmacy}).uncheckedCount,
        tagged.pickupItems.length,
      );
    });

    test('a batched pickup checks items of both orders', () async {
      await acceptOrder(batched: true);
      await arrive();
      expect(current().tasks, hasLength(2));
      final total = current().tasks.fold(0, (sum, t) => sum + t.items.length);
      expect(current().uncheckedCount, total);

      await trip().checkAllItems();
      await trip().pickedUp();
      expect(
        current().tasks.every((t) => t.timeOf(OrderEventType.pickedUp) != null),
        isTrue,
      );
    });

    test('leaving and resuming keeps the step and the checklist', () async {
      await acceptOrder();
      await arrive();
      final task = current().tasks.first;
      await trip().setItemChecked((
        orderId: task.orderId,
        index: 0,
      ), checked: true);
      await trip().setBag(sealed: true);

      trip().reset();
      await trip().restore();

      expect(current().status, TripStatus.atStore);
      expect(current().tasks.first.items.first.isPicked, isTrue);
      expect(current().bagSealed, isTrue);
    });
  });

  group('Waiting pay', () {
    test(
      'accrues ₹1 a minute after 5 minutes and is paid on delivery',
      () async {
        await acceptOrder();
        await arrive();
        clock.advance(const Duration(minutes: 4, seconds: 59));
        expect(current().isWaitingPaid(clock.now()), isFalse);
        expect(current().waitingPaiseAt(clock.now()), 0);

        clock.advance(const Duration(minutes: 3, seconds: 1));
        expect(current().waitingPaiseAt(clock.now()), 300);

        await trip().checkAllItems();
        await trip().pickedUp();
        clock.advance(const Duration(minutes: 10));
        expect(current().waitingPaiseAt(clock.now()), 300);

        services.demo!.jumpToNextStop();
        final task = current().currentTask;
        await trip().arrivedAtCustomer();
        final delivered = await trip().completeDelivery(
          DeliveryProof(
            method: task.requiredProof,
            capturedAt: clock.now(),
            otpVerified: true,
            photo: const MediaRef.sample('door'),
          ),
        );
        expect(delivered.payout.waitingPaise, 300);
      },
    );
  });

  group('Store issues', () {
    test('scenario 6: not ready, wait 6 min, item missing removed', () async {
      await acceptOrder(payment: PaymentMode.cod);
      await arrive();

      final notReady = await trip().reportStoreIssue(
        const StoreIssueRequest(type: IssueType.orderNotReady),
      );
      expect(notReady.outcome, IssueOutcome.waiting);
      await trip().checkAllItems();
      await expectLater(trip().pickedUp(), failsWith('still preparing'));

      clock.advance(const Duration(minutes: 6));
      expect(current().isOrderReady(clock.now()), isTrue);
      expect(current().waitingPaiseAt(clock.now()), 100);

      final task = current().tasks.first;
      final payout = task.payout;
      final removedValue = task.items.first.linePaise;
      final result = await trip().reportStoreIssue(
        itemIssue(task, [0], ItemResolution.remove),
      );

      expect(result.outcome, IssueOutcome.removed);
      expect(result.message, contains('your pay is unchanged'));
      final after = current().tasks.first;
      expect(after.items.first.status, ItemStatus.removed);
      expect(
        after.payment.orderValuePaise,
        task.payment.orderValuePaise - removedValue,
      );
      expect(after.payment.amountToCollectPaise, after.payment.orderValuePaise);
      expect(after.payout, payout);
      expect(after.issues.map((i) => i.type), [
        IssueType.orderNotReady,
        IssueType.itemMissing,
      ]);

      await trip().pickedUp();
      expect(current().status, TripStatus.inProgress);
    });

    test('a replaced item must be checked again', () async {
      await acceptOrder();
      await arrive();
      await trip().checkAllItems();
      final task = current().tasks.first;

      final result = await trip().reportStoreIssue(
        StoreIssueRequest(
          type: IssueType.itemDamaged,
          items: [(orderId: task.orderId, index: 0)],
          resolution: ItemResolution.replace,
        ),
      );

      expect(result.outcome, IssueOutcome.replaced);
      final item = current().tasks.first.items.first;
      expect(item.status, ItemStatus.replaced);
      expect(item.isPicked, isFalse);
      expect(current().uncheckedCount, 1);
      expect(current().tasks.first.payment, task.payment);
    });

    test('removing every item cancels with compensation', () async {
      await acceptOrder();
      await arrive();
      clock.advance(const Duration(minutes: 7));
      final task = current().tasks.first;

      final result = await trip().reportStoreIssue(
        itemIssue(task, [
          for (var i = 0; i < task.items.length; i++) i,
        ], ItemResolution.remove),
      );

      expect(result.outcome, IssueOutcome.cancelled);
      final cancellation = trip().cancellation!;
      expect(cancellation.atStore, isTrue);
      expect(cancellation.compensationPaise, 1500);
      expect(cancellation.waitingPaise, 200);
    });

    test('a batched order with every item removed leaves the trip', () async {
      await acceptOrder(batched: true);
      await arrive();
      final first = current().tasks.first;
      final second = current().tasks.last;

      final result = await trip().reportStoreIssue(
        itemIssue(first, [
          for (var i = 0; i < first.items.length; i++) i,
        ], ItemResolution.remove),
      );

      expect(result.outcome, IssueOutcome.removed);
      expect(result.message, contains(first.displayId));
      expect(current().tasks.map((t) => t.orderId), [second.orderId]);
      await services.history.load();
      expect(services.history.items.first.orderId, first.orderId);
      expect(services.history.items.first.status, OrderStatus.cancelled);
    });

    test('store closed needs the geofence, then cancels', () async {
      await acceptOrder();
      const closed = StoreIssueRequest(type: IssueType.storeClosed);

      await expectLater(trip().reportStoreIssue(closed), failsWith('200 m'));

      services.demo!.jumpToNextStop();
      final result = await trip().reportStoreIssue(closed);
      expect(result.outcome, IssueOutcome.cancelled);
      expect(trip().cancellation!.reason, contains('closed'));
      expect(trip().cancellation!.compensationPaise, 1500);
    });

    test('wrong order: re-check after the store fixes it', () async {
      await acceptOrder();
      await arrive();
      await trip().checkAllItems();

      await trip().reportStoreIssue(
        const StoreIssueRequest(type: IssueType.wrongOrder),
      );
      expect(current().uncheckedCount, current().pickupItems.length);
      await trip().checkAllItems();
      await expectLater(trip().pickedUp(), failsWith('fixing the order'));

      clock.advance(const Duration(seconds: 60));
      await trip().pickedUp();
      expect(current().status, TripStatus.inProgress);
    });

    test('Skip wait ends a store delay and logs it', () async {
      await acceptOrder();
      await arrive();
      await trip().reportStoreIssue(
        const StoreIssueRequest(type: IssueType.orderNotReady),
      );
      expect(services.demo!.skipStoreWait(), isTrue);
      await waitFor(() => current().isOrderReady(clock.now()));

      expect(current().waitingPaiseAt(clock.now()), 100);
      expect(
        current().tasks.first.timeline.last.note,
        'Store wait skipped (demo)',
      );
      expect(services.demo!.skipStoreWait(), isFalse);
    });

    test('after 15 min of a late order, cancel with compensation', () async {
      await acceptOrder();
      await arrive();
      await trip().reportStoreIssue(
        const StoreIssueRequest(type: IssueType.orderNotReady),
      );
      clock.advance(const Duration(minutes: 7));
      await trip().reportStoreIssue(
        const StoreIssueRequest(type: IssueType.orderNotReady),
      );
      clock.advance(const Duration(minutes: 7));
      await expectLater(trip().cancelAfterLongWait(), failsWith('15 min'));

      clock.advance(const Duration(minutes: 1));
      expect(current().canCancelForWaitAt(clock.now()), isTrue);
      await trip().cancelAfterLongWait();

      expect(trip().cancellation!.totalPaise, 1500 + 1000);
    });
  });

  group('Cancellations', () {
    test('scenario 21: customer cancels on the way, under 500 m', () async {
      await acceptOrder();
      expect(services.demo!.cancelTrip(CancelledBy.customer), isTrue);
      await waitFor(() => trip().cancellation != null);

      final cancellation = trip().cancellation!;
      expect(cancellation.atStore, isFalse);
      expect(cancellation.totalPaise, 0);
      expect(services.navigation.leg, isNull);

      await trip().closeCancelledTrip();
      expect(trip().hasTrip, isFalse);
      expect(services.availability.isOnline, isTrue);
      await services.history.load();
      expect(services.history.items.first.status, OrderStatus.cancelled);
    });

    test('heading to store pays ₹15 after 500 m', () async {
      await acceptOrder();
      final location = services.location as SimulatedLocationSource;
      expect(services.navigation.remainingM, greaterThan(600));
      clock.advance(const Duration(minutes: 2));
      location.advance();
      expect(services.navigation.travelledM, greaterThan(500));

      services.demo!.cancelTrip(CancelledBy.store);
      await waitFor(() => trip().cancellation != null);
      expect(trip().cancellation!.compensationPaise, 1500);

      await trip().closeCancelledTrip();
      await services.earnings.load();
      final entry = services.earnings.entries.firstWhere(
        (e) => e.type == EarningType.compensation,
      );
      expect(entry.amountPaise, 1500);
    });

    test('at the store: ₹15 plus waiting pay, after "leaving"', () async {
      await acceptOrder();
      await arrive();
      clock.advance(const Duration(minutes: 9));
      services.demo!.cancelTrip(CancelledBy.customer);
      await waitFor(() => trip().cancellation != null);

      final cancellation = trip().cancellation!;
      expect(cancellation.atStore, isTrue);
      expect(cancellation.compensationPaise, 1500);
      expect(cancellation.waitingPaise, 400);
      await expectLater(trip().pickedUp(), failsWith('cancelled'));

      final closed = await trip().closeCancelledTrip();
      expect(closed.totalPaise, 1900);
      await services.earnings.load();
      final types = services.earnings.entries.take(2).map((e) => e.type);
      expect(
        types,
        containsAll([EarningType.compensation, EarningType.waitingPay]),
      );
    });
  });

  group('Offline', () {
    test('steps are queued offline and sync on reconnect', () async {
      await acceptOrder();
      services.demo!.networkAvailable = false;

      await arrive();
      expect(current().status, TripStatus.atStore);
      expect(current().hasQueuedSteps, isTrue);
      expect(current().tasks.first.timeline.last.queued, isTrue);

      await trip().checkAllItems();
      await trip().pickedUp();
      expect(current().hasQueuedSteps, isTrue);

      services.demo!.networkAvailable = true;
      await waitFor(() => !current().hasQueuedSteps);
    });
  });
}
