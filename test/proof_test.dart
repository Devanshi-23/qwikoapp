import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/controllers/active_trip_controller.dart';
import 'package:qwiko_delivery_agent/controllers/navigation_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/core/formatters.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/delivery_check.dart';
import 'package:qwiko_delivery_agent/models/media_ref.dart';
import 'package:qwiko_delivery_agent/models/order.dart';

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
  group('Change calculation', () {
    CashCheck cash(int due, int received, {int upi = 0}) => CashCheck(
      duePaise: due * 100,
      receivedPaise: received * 100,
      upiPaise: upi * 100,
    );

    test('exact amount: no change', () {
      final check = cash(248, 248);
      expect(check.isEnough, isTrue);
      expect(check.changePaise, 0);
      expect(check.cashCollectedPaise, 24800);
      expect(check.error, isNull);
    });

    test('over: change to the rupee, cash in hand counts the amount due', () {
      final check = cash(248, 500);
      expect(check.changePaise, 25200);
      expect(check.cashCollectedPaise, 24800);
      expect(check.likelyTypo, isFalse);
    });

    test('under: short by the difference', () {
      final check = cash(248, 200);
      expect(check.isEnough, isFalse);
      expect(check.shortPaise, 4800);
      expect(check.error, contains('₹48'));
    });

    test('large typo: over ₹2,000 more than due is flagged', () {
      expect(cash(248, 2248).likelyTypo, isFalse);
      expect(cash(248, 2249).likelyTypo, isTrue);
    });

    test('split: UPI lowers the cash due', () {
      final check = cash(248, 200, upi: 48);
      expect(check.cashDuePaise, 20000);
      expect(check.isEnough, isTrue);
      expect(check.changePaise, 0);
    });
  });

  group('With an active drop', () {
    late FakeClock clock;
    late AppServices services;

    setUp(() {
      services = AppServices.demo(
        clock: clock = FakeClock(DateTime(2026, 10, 13, 14)),
        latency: Duration.zero,
        firstOfferDelay: const Duration(minutes: 30),
        offerInterval: const Duration(minutes: 30),
      );
      services.demo!.tipAfterDelivery = false;
    });

    tearDown(() => services.dispose());

    ActiveTripController trip() => services.trip;
    DeliveryTask task() => services.trip.currentTask!;

    Future<void> waitForRoute() => waitFor(
      () =>
          services.navigation.status == RouteStatus.ready &&
          !services.navigation.isPlanning,
    );

    Future<void> atCustomer({PaymentMode payment = PaymentMode.cod}) async {
      await services.session.signInWithEmail(
        email: 'arjun@example.com',
        password: 'password123',
      );
      await services.wallet.load();
      await services.availability.goOnline();
      services.demo!.sendOffer(OfferRequest(payment: payment));
      await waitFor(() => services.offers.offer != null);
      await services.offers.accept();
      await waitForRoute();
      services.demo!.jumpToNextStop();
      await trip().arrivedAtStore();
      await trip().checkAllItems();
      await trip().pickedUp();
      await waitForRoute();
      services.demo!.jumpToNextStop();
      await trip().arrivedAtCustomer();
    }

    DeliveryProof proofFor(
      DeliveryTask task, {
      bool otp = true,
      bool photo = true,
      int? cash,
      int change = 0,
    }) => DeliveryProof(
      method: task.requiredProof,
      capturedAt: clock.now(),
      otpVerified: otp,
      photo: photo ? const MediaRef.sample('door') : null,
      cashCollectedPaise: cash ?? task.payment.amountToCollectPaise,
      changeGivenPaise: change,
    );

    test('the checklist lists every missing step', () async {
      await atCustomer();
      final check = DeliveryCheck(task: task());
      expect(check.isComplete, isFalse);
      expect(
        check.missing,
        containsAll([
          if (task().requiredProof.needsOtp) 'OTP verified',
          if (task().requiredProof.needsPhoto) 'Delivery photo',
          '${formatPaise(task().payment.amountToCollectPaise)} collected',
        ]),
      );
    });

    test('three wrong codes lock entry for 30 s', () async {
      await atCustomer();
      final right = services.demo!.customerOtp!;
      final wrong = right == '1111' ? '2222' : '1111';

      var result = await trip().verifyDeliveryOtp(wrong);
      expect(result.attemptsLeft, 2);
      result = await trip().verifyDeliveryOtp(wrong);
      expect(result.attemptsLeft, 1);
      result = await trip().verifyDeliveryOtp(wrong);
      expect(result.lockedUntil, clock.now().add(const Duration(seconds: 30)));

      await expectLater(
        trip().verifyDeliveryOtp(right),
        failsWith('Try again in 0:30'),
      );
      clock.advance(const Duration(seconds: 30));
      result = await trip().verifyDeliveryOtp(right);
      expect(result.verified, isTrue);
      expect(task().timeline.last.note, 'OTP verified');
    });

    test('completion needs the required proof and the full amount', () async {
      await atCustomer();
      final t = task();
      if (t.requiredProof.needsOtp) {
        await expectLater(
          trip().completeDelivery(proofFor(t, otp: false)),
          failsWith('Verify the customer OTP'),
        );
      }
      if (t.requiredProof.needsPhoto) {
        await expectLater(
          trip().completeDelivery(proofFor(t, photo: false)),
          failsWith('Add a delivery photo'),
        );
      }
      await expectLater(
        trip().completeDelivery(
          proofFor(t, cash: t.payment.amountToCollectPaise - 100),
        ),
        failsWith('Collect ₹1 more'),
      );
    });

    test('cash in hand adds the amount due minus own-cash change', () async {
      await atCustomer();
      await services.wallet.load();
      final before = services.wallet.cash.balancePaise;
      final t = task();
      await trip().completeDelivery(proofFor(t, change: 2000));
      await services.wallet.load();
      expect(
        services.wallet.cash.balancePaise,
        before + t.payment.amountToCollectPaise - 2000,
      );
    });

    test('UPI: success is logged, failure and offline are reported', () async {
      await atCustomer();
      final due = task().payment.amountToCollectPaise;

      services.demo!.upiPaymentFails = true;
      expect(await trip().collectUpi(due), isFalse);
      services.demo!.upiPaymentFails = false;
      expect(await trip().collectUpi(due), isTrue);
      expect(task().timeline.last.type, OrderEventType.paymentCollected);

      services.demo!.networkAvailable = false;
      await expectLater(
        trip().collectUpi(due),
        throwsA(isA<NetworkUnavailableFailure>()),
      );
    });

    test('a delivery made offline is queued and syncs later', () async {
      await atCustomer(payment: PaymentMode.prepaid);
      services.demo!.networkAvailable = false;
      final delivered = await trip().completeDelivery(proofFor(task()));
      expect(delivered.timeline.last.queued, isTrue);

      services.demo!.networkAvailable = true;
      await services.history.fetch();
      final record = services.history.items.firstWhere(
        (o) => o.orderId == delivered.orderId,
      );
      expect(record.timeline.any((e) => e.queued), isFalse);
    });
  });
}
