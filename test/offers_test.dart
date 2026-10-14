import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/controllers/demo_controller.dart';
import 'package:qwiko_delivery_agent/controllers/offer_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/data/demo/demo_catalog.dart';
import 'package:qwiko_delivery_agent/data/demo/demo_order_factory.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/activity.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/models/trip.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

Future<void> waitFor(bool Function() condition, {int tries = 100}) async {
  for (var i = 0; i < tries && !condition(); i++) {
    await settle();
  }
  expect(condition(), isTrue, reason: 'condition not met in time');
}

void main() {
  late FakeClock clock;
  late AppServices services;
  late List<OfferOutcome> outcomes;
  late StreamSubscription<OfferOutcome> outcomeSubscription;

  AppServices build({Duration takenAfter = const Duration(milliseconds: 20)}) =>
      AppServices.demo(
        clock: clock = FakeClock(DateTime(2026, 10, 13, 14)),
        latency: Duration.zero,
        firstOfferDelay: const Duration(minutes: 30),
        offerInterval: const Duration(minutes: 30),
        offerTakenAfter: takenAfter,
      );

  void start(AppServices built) {
    services = built;
    outcomes = [];
    outcomeSubscription = services.offers.outcomes.listen(outcomes.add);
  }

  setUp(() => start(build()));

  tearDown(() async {
    await outcomeSubscription.cancel();
    services.dispose();
  });

  OfferController offers() => services.offers;
  DemoController demo() => services.demo!;

  Future<void> goOnline() async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.wallet.load();
    await services.availability.goOnline();
  }

  Future<DeliveryOffer> send([
    OfferRequest request = const OfferRequest(),
  ]) async {
    final before = offers().offer?.id;
    final queued = offers().queuedCount;
    expect(demo().sendOffer(request), isTrue);
    await waitFor(
      () => offers().offer?.id != before || offers().queuedCount > queued,
    );
    return offers().offer!;
  }

  List<ActivityEvent> activity(ActivityType type) =>
      services.availability.recentEvents.where((e) => e.type == type).toList();

  test('accepting creates a trip and logs the decision', () async {
    await goOnline();
    final offer = await send();
    expect(offer.shownAt, clock.now());

    final trip = await offers().accept();

    expect(services.trip.trip, trip);
    expect(offers().offer, isNull);
    expect(offers().isListening, isFalse);
    final task = trip.tasks.single;
    expect(task.orderId, offer.orders.single.orderId);
    expect(task.timeline.map((e) => e.type), contains(OrderEventType.accepted));
    await settle();
    expect(outcomes, [OfferOutcome.accepted]);
    expect(
      activity(ActivityType.offerAccepted).first.details,
      offer.displayIds,
    );
  });

  test('declines are logged with and without a note', () async {
    await goOnline();
    final stats = services.availability.acceptance;

    final first = await send();
    await offers().decline(DeclineReason.tooFar);
    final second = await send();
    await offers().decline(DeclineReason.other, note: '  Tyre puncture  ');
    await settle();

    final declined = activity(ActivityType.offerDeclined);
    expect(declined[0].details, '${second.displayIds} · Other: Tyre puncture');
    expect(declined[1].details, '${first.displayIds} · Too far');
    expect(outcomes, [OfferOutcome.declined, OfferOutcome.declined]);
    expect(services.availability.acceptance.declined, stats.declined + 2);
  });

  test('declining is never blocked by a failed request', () async {
    await goOnline();
    await send();
    demo().failNext(OperationType.declineOffer);

    await offers().decline(DeclineReason.lowPayout);

    expect(offers().offer, isNull);
  });

  test('an unanswered offer times out as missed', () async {
    await goOnline();
    final stats = services.availability.acceptance;
    final offer = await send();
    expect(offers().remaining, const Duration(seconds: 30));

    clock.advance(const Duration(seconds: 31));
    await waitFor(() => offers().offer == null, tries: 400);
    await settle();

    expect(outcomes, [OfferOutcome.missed]);
    expect(activity(ActivityType.offerMissed).first.details, offer.displayIds);
    expect(services.availability.acceptance.missed, stats.missed + 1);
  });

  test('an offer can expire in 5 seconds', () async {
    await goOnline();
    final offer = await send(const OfferRequest(timeoutSeconds: 5));
    expect(offer.timeoutSeconds, 5);
    expect(offers().remaining, const Duration(seconds: 5));
  });

  test('assistive technology doubles the time once', () async {
    await goOnline();
    await send();
    offers().extendTime();
    offers().extendTime();
    expect(offers().offer!.timeoutSeconds, 60);
    expect(offers().hasExtraTime, isTrue);
  });

  test('one offer is shown at a time and the rest queue', () async {
    await goOnline();
    final first = await send();
    await send();
    expect(offers().offer!.id, first.id);
    expect(offers().queuedCount, 1);

    clock.advance(const Duration(seconds: 10));
    await offers().decline(DeclineReason.tooFar);

    final second = offers().offer!;
    expect(second.id, isNot(first.id));
    expect(second.shownAt, clock.now());
    expect(offers().queuedCount, 0);
  });

  test('queued offers older than 60 seconds are dropped', () async {
    await goOnline();
    await send();
    await send();

    clock.advance(const Duration(seconds: 61));
    await offers().decline(DeclineReason.tooFar);

    expect(offers().offer, isNull);
    expect(offers().queuedCount, 0);
  });

  test('an offer taken by someone else becomes unavailable', () async {
    await goOnline();
    final stats = services.availability.acceptance;
    demo().takeNextOffer = true;
    final offer = await send();

    await waitFor(() => offers().isUnavailable);
    expect(offers().offer!.id, offer.id);
    await expectLater(
      offers().accept(),
      throwsA(isA<OfferUnavailableFailure>()),
    );

    offers().dismissUnavailable();
    await settle();
    expect(offers().offer, isNull);
    expect(outcomes, [OfferOutcome.withdrawn]);
    expect(activity(ActivityType.offerWithdrawn), hasLength(1));
    expect(services.availability.acceptance.offered, stats.offered);
    expect(demo().takeNextOffer, isFalse);
  });

  test('accepting an offer that was already taken fails', () async {
    await outcomeSubscription.cancel();
    services.dispose();
    start(build(takenAfter: const Duration(minutes: 5)));
    await goOnline();
    demo().takeNextOffer = true;
    await send();

    await expectLater(
      offers().accept(),
      throwsA(isA<OfferUnavailableFailure>()),
    );
    expect(offers().isUnavailable, isTrue);
    expect(services.trip.hasTrip, isFalse);
  });

  test('losing the connection releases the offer without a miss', () async {
    await goOnline();
    final missed = services.availability.acceptance.missed;
    await send();

    demo().networkAvailable = false;
    await settle();

    expect(offers().offer, isNull);
    expect(outcomes, [OfferOutcome.released]);
    expect(services.availability.acceptance.missed, missed);
    expect(services.availability.isOnline, isTrue);
    demo().networkAvailable = true;
  });

  test('COD over the cash limit blocks accept; prepaid stays open', () async {
    await goOnline();
    demo().setCashInHand(DemoController.nearLimitCashPaise);
    await waitFor(
      () =>
          services.wallet.cash.balancePaise ==
          DemoController.nearLimitCashPaise,
    );

    final cod = await send(const OfferRequest(payment: PaymentMode.cod));
    expect(cod.codAmountPaise, greaterThan(15000));
    expect(offers().acceptBlockedReason, contains('Deposit cash'));
    expect(offers().acceptBlockedReason, contains('₹150'));
    await expectLater(offers().accept(), throwsA(isA<NotAllowedFailure>()));

    await offers().decline(DeclineReason.other);
    final prepaid = await send(
      const OfferRequest(payment: PaymentMode.prepaid),
    );
    expect(prepaid.isCod, isFalse);
    expect(offers().acceptBlockedReason, isNull);
    await offers().accept();
    expect(services.trip.hasTrip, isTrue);
  });

  test('a batched offer has two drops from one store', () async {
    await goOnline();
    final offer = await send(const OfferRequest(batched: true));

    expect(offer.isBatched, isTrue);
    expect(offer.drops, hasLength(2));
    expect(offer.orders.map((o) => o.store.id).toSet(), hasLength(1));
    expect(offer.payout.batchBonusPaise, DemoOrderFactory.batchBonusPaise);
    expect(offer.payout.basePaise, DemoOrderFactory.basePaise * 2);
    expect(
      offer.payout.totalPaise,
      offer.orders.fold(0, (sum, o) => sum + o.payout.totalPaise),
    );
    expect(
      offer.tripDistanceM,
      greaterThan(offer.distanceToPickupM + offer.orders.first.distanceM - 1),
    );

    final trip = await offers().accept();
    expect(trip.tasks, hasLength(2));
  });

  test('payout formula matches the plan example', () {
    expect(DemoOrderFactory.payoutFor(tripDistanceM: 4800).totalPaise, 4200);
    expect(
      DemoOrderFactory.payoutFor(tripDistanceM: 1500, batched: true).totalPaise,
      3500,
    );
  });

  test('cycles are never offered heavy items', () {
    final factory = DemoOrderFactory(Random(7));
    for (var i = 0; i < 200; i++) {
      final items = factory.buildItems(demoStores.first, allowHeavy: false);
      expect(factory.tagsFor(items), isNot(contains(OfferTag.heavy)));
    }
  });

  test('sending an offer while offline does nothing', () async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    expect(demo().sendOffer(const OfferRequest()), isFalse);
  });
}
