import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/controllers/availability_controller.dart';
import 'package:qwiko_delivery_agent/controllers/demo_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/activity.dart';
import 'package:qwiko_delivery_agent/models/availability.dart';
import 'package:qwiko_delivery_agent/models/media_ref.dart';
import 'package:qwiko_delivery_agent/models/money.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/models/partner.dart';
import 'package:qwiko_delivery_agent/models/trip.dart';
import 'package:qwiko_delivery_agent/models/zone.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await settle();
  }
  expect(condition(), isTrue, reason: 'condition not met in time');
}

void main() {
  late FakeClock clock;
  late AppServices services;

  AppServices build(DateTime now) => AppServices.demo(
    clock: clock = FakeClock(now),
    latency: Duration.zero,
    firstOfferDelay: const Duration(milliseconds: 1),
    offerInterval: const Duration(milliseconds: 1),
  );

  setUp(() => services = build(DateTime(2026, 10, 13, 14)));

  tearDown(() => services.dispose());

  AvailabilityController availability() => services.availability;

  Future<void> signIn() async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.wallet.load();
  }

  List<OnlineBlockerType> blockerTypes() =>
      availability().blockers.map((b) => b.type).toList();

  Future<void> acceptOffer() async {
    await availability().goOnline();
    await waitFor(() => services.offers.offer != null);
    await services.offers.accept();
  }

  Future<void> finishTrip() async {
    final trip = services.trip;
    services.demo!.jumpToNextStop();
    await trip.arrivedAtStore();
    await trip.checkAllItems();
    await trip.pickedUp();
    while (trip.hasTrip) {
      final task = trip.currentTask!;
      services.demo!.jumpToNextStop();
      await trip.arrivedAtCustomer();
      await trip.completeDelivery(
        DeliveryProof(
          method: task.requiredProof,
          capturedAt: clock.now(),
          otpVerified: true,
          photo: const MediaRef.sample('door'),
          cashCollectedPaise: task.payment.amountToCollectPaise,
        ),
      );
    }
  }

  group('Online blockers', () {
    test('expired licence and ₹2,150 cash give two blockers', () async {
      await signIn();
      services.demo!.blockGoingOnline();
      await settle();

      expect(blockerTypes(), [
        OnlineBlockerType.documentExpired,
        OnlineBlockerType.cashLimitReached,
      ]);
      expect(
        services.wallet.cash.balancePaise,
        DemoController.blockedCashPaise,
      );
      await expectLater(
        availability().goOnline(),
        throwsA(isA<NotAllowedFailure>()),
      );
      expect(availability().isOnline, isFalse);
    });

    test('fixing each blocker re-enables going online', () async {
      await signIn();
      services.demo!.blockGoingOnline();
      await settle();

      await services.wallet.depositCash(
        services.wallet.cash.balancePaise,
        DepositMethod.storeCounter,
      );
      await settle();
      expect(blockerTypes(), [OnlineBlockerType.documentExpired]);

      await services.profile.saveDocuments({
        DocumentType.license: const MediaRef.sample('doc-license'),
      });
      await settle();
      expect(availability().blockers, isEmpty);

      await availability().goOnline();
      expect(availability().isOnline, isTrue);
    });

    test('the server refuses even if the app skips its own check', () async {
      await signIn();
      services.demo!.setCashInHand(250000);
      // The wallet has not refreshed yet in this instant on a slow network;
      // reset it so the client-side check passes.
      services.wallet.reset();
      expect(blockerTypes(), isEmpty);
      await expectLater(
        availability().goOnline(),
        throwsA(isA<NotAllowedFailure>()),
      );
    });

    test('cash below the limit does not block', () async {
      await signIn();
      services.demo!.setCashInHand(199900);
      await settle();
      expect(blockerTypes(), isEmpty);
    });

    test('location and network blockers follow the device state', () async {
      await signIn();
      services.demo!.locationPermissionGranted = false;
      services.demo!.networkAvailable = false;
      expect(blockerTypes(), [
        OnlineBlockerType.locationPermissionOff,
        OnlineBlockerType.networkOffline,
      ]);

      await services.device.requestLocationPermission();
      services.demo!.networkAvailable = true;
      expect(availability().blockers, isEmpty);
    });

    test('pending verification and suspension block going online', () async {
      services.demo!.useAccount(DemoAccount.pending);
      await signIn();
      expect(blockerTypes(), [OnlineBlockerType.verificationPending]);

      services.demo!.useAccount(DemoAccount.suspended);
      await services.session.refreshPartner();
      expect(blockerTypes(), [OnlineBlockerType.accountSuspended]);
    });

    test(
      'a blocker that appears while online takes the rider offline',
      () async {
        await signIn();
        await availability().goOnline();
        services.demo!.setCashInHand(DemoController.blockedCashPaise);
        await settle();

        expect(availability().isOnline, isFalse);
        expect(availability().notice, contains('Deposit cash'));
        expect(services.offers.isListening, isFalse);
      },
    );

    test('a blocker during a trip waits until the trip ends', () async {
      await signIn();
      await acceptOffer();
      services.demo!.expireDocument();
      await settle();
      expect(availability().isOnline, isTrue);

      await finishTrip();
      await settle();
      expect(availability().isOnline, isFalse);
      expect(availability().notice, contains('Driving Licence'));
    });

    test('losing the network does not take the rider offline', () async {
      await signIn();
      await availability().goOnline();
      services.demo!.networkAvailable = false;
      await settle();
      expect(availability().isOnline, isTrue);
    });
  });

  group('Going offline', () {
    test('is refused during an active order with the reason', () async {
      await signIn();
      await acceptOffer();
      await expectLater(
        availability().goOffline(),
        throwsA(
          isA<NotAllowedFailure>().having(
            (f) => f.message,
            'message',
            AvailabilityController.activeOrderReason,
          ),
        ),
      );
    });

    test(
      'warns when the next daily reward is 3 orders or fewer away',
      () async {
        await signIn();
        await services.incentives.load();
        final daily = services.incentives.todayMilestone!;
        expect(daily.type, IncentiveType.dailyMilestone);

        for (
          var i = 0;
          i < 8 && services.incentives.rewardAtRisk == null;
          i++
        ) {
          await acceptOffer();
          await finishTrip();
          await settle();
        }
        final risk = services.incentives.rewardAtRisk!;
        final next = services.incentives.todayMilestone!.nextTier!;
        expect(risk.orders, inInclusiveRange(1, 3));
        expect(risk.rewardPaise, next.rewardPaise);
      },
    );
  });

  group('Break mode', () {
    test('pauses offers and is logged', () async {
      await signIn();
      await availability().goOnline();
      await waitFor(() => services.offers.offer != null);

      await availability().startBreak(const Duration(minutes: 15));
      expect(availability().status, AvailabilityStatus.onBreak);
      expect(availability().breakRemaining, const Duration(minutes: 15));
      expect(services.offers.offer, isNull);
      expect(services.offers.isListening, isFalse);

      await availability().endBreak();
      expect(availability().status, AvailabilityStatus.online);
      await waitFor(() => services.offers.offer != null);

      await settle();
      final types = availability().recentEvents.map((e) => e.type).toList();
      expect(types.take(2), [
        ActivityType.breakEnded,
        ActivityType.breakStarted,
      ]);
    });

    test('cannot start during an active order', () async {
      await signIn();
      await acceptOffer();
      await expectLater(
        availability().startBreak(const Duration(minutes: 15)),
        throwsA(isA<NotAllowedFailure>()),
      );
    });

    test('break time is not counted as online time', () async {
      await signIn();
      await availability().loadActivity();
      final before = availability().onlineToday;

      await availability().goOnline();
      clock.advance(const Duration(minutes: 10));
      await availability().startBreak(const Duration(minutes: 15));
      clock.advance(const Duration(minutes: 15));
      await availability().endBreak();
      clock.advance(const Duration(minutes: 5));
      await settle();

      expect(availability().onlineToday - before, const Duration(minutes: 15));
    });
  });

  test('online time resets at midnight', () async {
    services.dispose();
    services = build(DateTime(2026, 10, 13, 23, 30));
    await signIn();
    await availability().goOnline();
    clock.advance(const Duration(hours: 1));
    await availability().loadActivity();

    expect(availability().onlineToday, const Duration(minutes: 30));
  });

  test(
    'acceptance rate counts declines and misses from the last 7 days',
    () async {
      await signIn();
      await availability().loadActivity();
      final before = availability().acceptance;
      expect(before.accepted, greaterThan(0));
      expect(before.rate, inExclusiveRange(0, 1.0001));

      await availability().goOnline();
      await waitFor(() => services.offers.offer != null);
      await services.offers.decline(DeclineReason.tooFar);
      await settle();

      final after = availability().acceptance;
      expect(after.declined, before.declined + 1);
      expect(after.rate!, lessThan(before.rate!));
    },
  );

  group('Zone demand', () {
    test('lunch peak makes central zones busy', () async {
      await signIn();
      await services.zones.load();
      final hottest = services.zones.hottestNearby(
        availability().zoneId,
        availability().position,
      )!;
      expect(hottest.name, 'Connaught Place');
      expect(hottest.demand, DemandLevel.high);
      expect(hottest.surgeMultiplier, 1.3);
    });

    test('off-peak hours are normal unless forced', () async {
      services.dispose();
      services = build(DateTime(2026, 10, 13, 16));
      await signIn();
      await services.zones.load();
      expect(
        services.zones.zones.every((z) => z.demand == DemandLevel.normal),
        isTrue,
      );

      services.demo!.demandOverride = DemandOverride.surge;
      await settle();
      expect(services.zones.byId('cp')!.demand, DemandLevel.surge);
    });

    test('moving to a zone updates the idle position', () async {
      await signIn();
      await services.zones.load();
      final cp = services.zones.byId('cp')!;
      availability().moveToZone(cp.id, cp.center);

      expect(availability().zoneId, 'cp');
      expect(availability().position, cp.center);
      expect(services.zones.hottestNearby('cp', cp.center)?.name, 'Karol Bagh');
    });
  });

  group('Cash in hand', () {
    test('deposits are validated and logged', () async {
      await signIn();
      services.demo!.setCashInHand(50000);
      await settle();

      await expectLater(
        services.wallet.depositCash(60000, DepositMethod.upi),
        throwsA(isA<ValidationFailure>()),
      );
      await services.wallet.depositCash(50000, DepositMethod.upi);
      await settle();

      expect(services.wallet.cash.balancePaise, 0);
      expect(
        availability().recentEvents.first.type,
        ActivityType.cashDeposited,
      );
    });
  });

  test('announcements can be dismissed', () async {
    await signIn();
    await services.notifications.load();
    final first = services.notifications.announcements.first;

    await services.notifications.dismissAnnouncement(first.id);
    await services.notifications.load();
    expect(
      services.notifications.announcements.any((a) => a.id == first.id),
      isFalse,
    );
  });
}
