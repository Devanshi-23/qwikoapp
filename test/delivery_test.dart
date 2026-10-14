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
import 'package:qwiko_delivery_agent/models/trip.dart';

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
  Future<void> waitForRoute() => waitFor(
    () =>
        services.navigation.status == RouteStatus.ready &&
        !services.navigation.isPlanning,
  );

  /// Accepts an offer and picks it up; the rider is heading to drop 1.
  Future<void> pickUp({
    bool batched = false,
    PaymentMode payment = PaymentMode.prepaid,
  }) async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.wallet.load();
    await services.availability.goOnline();
    services.demo!.sendOffer(OfferRequest(batched: batched, payment: payment));
    await waitFor(() => services.offers.offer != null);
    await services.offers.accept();
    await waitForRoute();
    services.demo!.jumpToNextStop();
    await trip().arrivedAtStore();
    await trip().checkAllItems();
    await trip().pickedUp();
    await waitForRoute();
  }

  Future<void> atCustomer() async {
    services.demo!.jumpToNextStop();
    await trip().arrivedAtCustomer();
  }

  group("I've arrived at the customer", () {
    test('is refused outside 100 m and allowed inside it', () async {
      await pickUp();
      expect(current().currentTask.status, OrderStatus.headingToCustomer);
      expect(trip().isNearCustomer, isFalse);
      await expectLater(trip().arrivedAtCustomer(), failsWith('within 100 m'));

      services.demo!.jumpToNextStop();
      expect(trip().isNearCustomer, isTrue);
      await trip().arrivedAtCustomer();
      expect(current().currentTask.status, OrderStatus.arrivedAtCustomer);
    });
  });

  group('Calling the customer', () {
    test('logs every attempt, answered or not', () async {
      await pickUp();
      final answered = await trip().callCustomer();
      expect(answered.answered, isTrue);
      expect(answered.duration, const Duration(seconds: 42));

      services.demo!.customerResponse = CustomerResponse.noAnswer;
      final missed = await trip().callCustomer();
      expect(missed.answered, isFalse);

      final task = current().currentTask;
      expect(task.callAttempts, 2);
      expect(task.contactAttempts, 2);
      expect(
        task.timeline
            .where((e) => e.type == OrderEventType.callAttempted)
            .map((e) => e.note),
        ['Answered · 0:42', 'No answer'],
      );
    });

    test('offline attempts are queued and sync later', () async {
      await pickUp();
      services.demo!.networkAvailable = false;
      await trip().callCustomer();
      await trip().sendChat('On my way');
      expect(
        current().currentTask.timeline.where((e) => e.queued),
        hasLength(2),
      );
      expect(current().hasQueuedSteps, isTrue);

      services.demo!.networkAvailable = true;
      await waitFor(() => !current().hasQueuedSteps);
    });
  });

  group('Chat', () {
    test('sends, validates length and gets a demo reply', () async {
      await pickUp();
      await expectLater(trip().sendChat('   '), failsWith('Type a message'));
      await expectLater(
        trip().sendChat('x' * 201),
        failsWith('up to 200 characters'),
      );

      await trip().sendChat('On my way');
      expect(current().currentTask.chat.single.note, 'On my way');

      await Future<void>.delayed(const Duration(milliseconds: 2100));
      await settle();
      final chat = current().currentTask.chat.toList();
      expect(chat, hasLength(2));
      expect(chat.last.type, OrderEventType.chatReceived);
    });
  });

  group('Mark undeliverable', () {
    test('needs 2 calls and a 5 minute wait, then starts the return', () async {
      await pickUp();
      await expectLater(
        trip().markUndeliverable(reason: 'No answer'),
        failsWith('Tap "I\'ve arrived" first'),
      );
      await atCustomer();
      final task = current().currentTask;
      expect(
        task.undeliverableBlockedReason(clock.now()),
        'Call the customer 2 more times and wait 5:00 more.',
      );
      await expectLater(
        trip().markUndeliverable(reason: 'No answer'),
        failsWith('Call the customer 2 more times'),
      );

      services.demo!.customerResponse = CustomerResponse.noAnswer;
      await trip().callCustomer();
      clock.advance(const Duration(minutes: 3));
      expect(
        current().currentTask.undeliverableBlockedReason(clock.now()),
        'Call the customer 1 more time and wait 2:00 more.',
      );
      await trip().callCustomer();
      clock.advance(const Duration(minutes: 2));
      expect(
        current().currentTask.undeliverableBlockedReason(clock.now()),
        isNull,
      );

      await trip().markUndeliverable(reason: "Customer isn't answering calls");
      final returnable = task.isReturnable;
      if (returnable) {
        expect(current().status, TripStatus.returningToStore);
        expect(current().currentTask.status, OrderStatus.returningToStore);
        expect(
          current().notice!.title,
          'Return ${task.displayId} to the store',
        );
        await waitForRoute();
        expect(services.navigation.leg!.key, endsWith(':return'));
        expect(services.navigation.leg!.toStore, isTrue);
      } else {
        expect(current().status, TripStatus.completed);
        expect(current().notice!.title, 'Keep or dispose as instructed');
      }
      expect(
        current().currentTask.issues.last.type,
        IssueType.customerUnreachable,
      );
    });

    test('a refusal skips the call and wait requirement', () async {
      await pickUp();
      await atCustomer();
      await trip().markUndeliverable(
        reason: 'Wrong or missing items',
        refused: true,
      );
      final task = current().tasks.first;
      expect(task.status, isNot(OrderStatus.arrivedAtCustomer));
      expect(task.issues.last.type, IssueType.customerRefused);
    });
  });

  group('Return to store', () {
    test('ends as returned with half pay plus distance pay', () async {
      await pickUp();
      await atCustomer();
      final before = current().currentTask;
      // A refusal needs no door wait, so the rider is still at the customer.
      await trip().markUndeliverable(reason: 'Refused', refused: true);

      if (!before.isReturnable) {
        // Non-returnable: paid now, the trip closes after the notice.
        final paid = current().tasks.first;
        expect(paid.status, OrderStatus.disposed);
        expect(paid.payout, before.failedPayout(returned: false));
        await trip().dismissNotice();
        expect(trip().trip, isNull);
        expect(trip().tripEarnedPaise, paid.payout.totalPaise);
        return;
      }

      await waitForRoute();
      services.demo!.locationPermissionGranted = false;
      await settle();
      await expectLater(
        trip().returnedToStore(),
        failsWith("confirm you're at the store"),
      );
      services.demo!.locationPermissionGranted = true;
      await settle();
      services.demo!.jumpToNextStop();
      expect(trip().isNearStore, isTrue);
      await trip().returnedToStore();

      expect(trip().trip, isNull);
      final expected = before.failedPayout(returned: true);
      expect(
        expected.compensationPaise,
        ((before.payout.orderPayPaise * 0.5) / 100).round() * 100 +
            before.payout.distancePaise,
      );
      expect(trip().tripEarnedPaise, expected.totalPaise);

      await services.history.fetch();
      final record = services.history.items.firstWhere(
        (o) => o.orderId == before.orderId,
      );
      expect(record.status, OrderStatus.returned);
      expect(record.payout, expected);

      await services.earnings.fetch();
      expect(
        services.earnings.entries.where(
          (e) =>
              e.type == EarningType.compensation && e.orderId == before.orderId,
        ),
        hasLength(1),
      );
    });
  });

  group("Can't find address", () {
    test('the customer shares a new pin and the route updates', () async {
      await pickUp();
      final before = current().currentTask.customer.location;
      final legBefore = services.navigation.leg!.key;

      await trip().requestCustomerLocation();
      final task = current().currentTask;
      expect(task.customer.location, isNot(before));
      expect(task.timeOf(OrderEventType.locationShared), clock.now());
      await waitForRoute();
      expect(services.navigation.leg!.key, isNot(legBefore));
      expect(services.navigation.leg!.to, task.customer.location);
    });

    test('a customer who never answers cannot share a pin', () async {
      await pickUp();
      services.demo!.customerResponse = CustomerResponse.noAnswer;
      await expectLater(
        trip().requestCustomerLocation(),
        failsWith("hasn't shared a location"),
      );
    });

    test('contact support raises a ticket on the order', () async {
      await pickUp();
      final ticket = await trip().contactSupportAboutAddress();
      expect(ticket, startsWith('TKT'));
      final issue = current().currentTask.issues.single;
      expect(issue.type, IssueType.addressNotFound);
      expect(issue.ticketId, ticket);
    });
  });

  group('Customer cancels mid-route', () {
    test('shows the reason and what to do with the order', () async {
      await pickUp();
      final task = current().currentTask;
      expect(services.demo!.cancelTrip(CancelledBy.customer), isTrue);
      await waitFor(() => current().notice != null);

      final notice = current().notice!;
      expect(notice.message, contains('The customer cancelled the order.'));
      if (task.isReturnable) {
        expect(current().status, TripStatus.returningToStore);
      } else {
        expect(notice.title, 'Keep or dispose as instructed');
        expect(current().tasks.first.status, OrderStatus.disposed);
      }
      expect(services.demo!.cancelTrip(CancelledBy.store), isFalse);
    });
  });

  group('Batched trip', () {
    test('a failed first drop lets the second continue first', () async {
      await pickUp(batched: true);
      expect(current().tasks, hasLength(2));
      await atCustomer();
      await trip().markUndeliverable(reason: 'Refused', refused: true);

      expect(current().currentTaskIndex, 1);
      expect(current().status, TripStatus.inProgress);
      expect(current().currentTask.status, OrderStatus.headingToCustomer);

      await waitForRoute();
      await atCustomer();
      final second = current().currentTask;
      final result = await trip().completeDelivery(
        DeliveryProof(
          method: second.requiredProof,
          capturedAt: clock.now(),
          otpVerified: true,
          photo: const MediaRef.sample('door'),
          cashCollectedPaise: second.payment.amountToCollectPaise,
        ),
      );
      expect(result.payout.batchBonusPaise, 0);
      final first = current().tasks.first;
      if (first.status == OrderStatus.returningToStore) {
        expect(current().status, TripStatus.returningToStore);
      } else {
        expect(current().status, TripStatus.completed);
        await trip().dismissNotice();
        expect(trip().trip, isNull);
      }
    });

    test('the batch bonus is paid when both drops are delivered', () async {
      await pickUp(batched: true);
      DeliveryTask? last;
      while (trip().hasTrip) {
        await waitForRoute();
        await atCustomer();
        final task = current().currentTask;
        last = await trip().completeDelivery(
          DeliveryProof(
            method: task.requiredProof,
            capturedAt: clock.now(),
            otpVerified: true,
            photo: const MediaRef.sample('door'),
            cashCollectedPaise: task.payment.amountToCollectPaise,
          ),
        );
      }
      expect(last!.payout.batchBonusPaise, greaterThan(0));
    });
  });
}
