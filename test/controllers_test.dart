import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/controllers/history_controller.dart';
import 'package:qwiko_delivery_agent/controllers/loadable_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/media_ref.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/models/partner.dart';
import 'package:qwiko_delivery_agent/models/trip.dart';

/// Lets queued microtasks and zero-length timers run.
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

  setUp(() {
    clock = FakeClock(DateTime(2026, 10, 13, 14));
    services = AppServices.demo(
      clock: clock,
      latency: Duration.zero,
      firstOfferDelay: const Duration(milliseconds: 1),
      offerInterval: const Duration(milliseconds: 1),
    );
  });

  tearDown(() => services.dispose());

  Future<void> signIn() => services.session.signInWithEmail(
    email: 'arjun@example.com',
    password: 'password123',
  );

  Future<void> deliverOneOrder() async {
    await services.availability.goOnline();
    await waitFor(() => services.offers.offer != null);
    await services.offers.accept();
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

  test('sign-in loads the seeded verified partner', () async {
    await signIn();

    expect(services.session.isSignedIn, isTrue);
    expect(services.profile.profile?.name, 'Arjun Mehta');
    expect(services.profile.profile?.verification, VerificationStatus.verified);
    expect(services.trip.hasTrip, isFalse);
  });

  test('sign-up with the seeded phone number is rejected', () async {
    expect(
      services.session.signUp(
        name: 'Someone Else',
        email: 'someone@example.com',
        phone: '9876543210',
        password: 'password123',
      ),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('a new sign-up starts with an empty account', () async {
    await services.session.signUp(
      name: 'Priya Nair',
      email: 'priya@example.com',
      phone: '9123456780',
      password: 'password123',
    );
    await services.history.load();
    await services.earnings.load();

    expect(
      services.profile.profile?.verification,
      VerificationStatus.newSignup,
    );
    expect(services.history.items, isEmpty);
    expect(services.earnings.todayPaise, 0);
  });

  test('dashboard data comes from the seed', () async {
    await signIn();
    await services.history.load();
    await services.earnings.load();
    await services.wallet.load();

    expect(services.history.recent, hasLength(3));
    expect(
      services.history.recent.every((t) => t.status == OrderStatus.delivered),
      isTrue,
    );
    expect(services.history.summary!.deliveredCount, greaterThan(0));
    expect(services.earnings.buckets, hasLength(7));
    expect(services.wallet.balance!.withdrawablePaise, greaterThan(0));
  });

  test('history pages and filters', () async {
    await signIn();
    await services.history.load();
    final firstPage = services.history.items.length;
    expect(firstPage, 20);
    expect(services.history.hasMore, isTrue);

    await services.history.loadMore();
    expect(services.history.items.length, greaterThan(firstPage));

    await services.history.setFilter(HistoryFilter.cancelled);
    expect(services.history.items, isNotEmpty);
    expect(
      services.history.items.every((t) => t.status == OrderStatus.cancelled),
      isTrue,
    );
  });

  test('delivering an order updates history, earnings and wallet', () async {
    await signIn();
    await services.history.load();
    await services.earnings.load();
    await services.wallet.load();
    final ordersBefore = services.earnings.todayOrders;
    final earnedBefore = services.earnings.todayPaise;
    final balanceBefore = services.wallet.balance!.withdrawablePaise;
    final deliveredBefore = services.history.summary!.deliveredCount;

    await deliverOneOrder();
    await settle();

    expect(services.trip.hasTrip, isFalse);
    expect(services.earnings.todayOrders, ordersBefore + 1);
    expect(services.earnings.todayPaise, greaterThan(earnedBefore));
    expect(
      services.wallet.balance!.withdrawablePaise,
      greaterThan(balanceBefore),
    );
    expect(services.history.summary!.deliveredCount, deliveredBefore + 1);
    expect(services.history.items.first.status, OrderStatus.delivered);
  });

  test('going offline and logging out are blocked during a trip', () async {
    await signIn();
    await services.availability.goOnline();
    await waitFor(() => services.offers.offer != null);
    await services.offers.accept();

    expect(services.trip.hasTrip, isTrue);
    expect(services.offers.isListening, isFalse);
    expect(
      services.availability.goOffline(),
      throwsA(isA<NotAllowedFailure>()),
    );
    expect(services.session.signOut(), throwsA(isA<NotAllowedFailure>()));
  });

  test('declining an offer moves on to the next one', () async {
    await signIn();
    await services.availability.goOnline();
    await waitFor(() => services.offers.offer != null);
    final first = services.offers.offer!;

    await services.offers.decline(DeclineReason.tooFar);
    expect(services.offers.offer?.id, isNot(first.id));
    await waitFor(() => services.offers.offer != null);
    expect(services.offers.offer!.id, isNot(first.id));
  });

  test('going offline drops the shown offer and stops listening', () async {
    await signIn();
    await services.availability.goOnline();
    await waitFor(() => services.offers.offer != null);

    await services.availability.goOffline();
    expect(services.offers.offer, isNull);
    expect(services.offers.isListening, isFalse);
  });

  test('online time counts the current session', () async {
    await signIn();
    await services.availability.loadActivity();
    final before = services.availability.onlineToday;

    await services.availability.goOnline();
    clock.advance(const Duration(minutes: 30));
    await settle();

    expect(
      services.availability.onlineToday - before,
      const Duration(minutes: 30),
    );
  });

  test('instant withdrawal is limited to once a day', () async {
    await signIn();
    await services.wallet.load();

    await services.wallet.withdraw(20000);
    await settle();
    expect(services.wallet.payouts.first.isInstant, isTrue);
    expect(services.wallet.alreadyWithdrewToday, isTrue);
    expect(services.wallet.withdraw(20000), throwsA(isA<ValidationFailure>()));
  });

  test('network failures surface as load errors and retry works', () async {
    await signIn();
    services.demo!.networkAvailable = false;
    await services.earnings.load();
    expect(services.earnings.status, LoadStatus.error);
    expect(services.earnings.error, contains('offline'));

    services.demo!.networkAvailable = true;
    await services.earnings.load();
    expect(services.earnings.isReady, isTrue);
  });

  test('injected failures hit only the next call', () async {
    await signIn();
    services.demo!.failNext(OperationType.loadWallet);
    await services.wallet.load();
    expect(services.wallet.status, LoadStatus.error);

    await services.wallet.load();
    expect(services.wallet.isReady, isTrue);
  });

  test('notifications can be read, dismissed and restored', () async {
    await signIn();
    await services.notifications.load();
    final notifications = services.notifications;
    expect(notifications.unreadCount, greaterThan(0));

    final first = notifications.items.first;
    await notifications.dismiss(first.id);
    expect(notifications.items.any((n) => n.id == first.id), isFalse);
    await notifications.restore(first);
    await settle();
    expect(notifications.items.any((n) => n.id == first.id), isTrue);

    await notifications.markAllRead();
    await settle();
    expect(notifications.unreadCount, 0);
  });

  test('sign-out clears account data', () async {
    await signIn();
    await services.history.load();
    await services.session.signOut();

    expect(services.session.isSignedIn, isFalse);
    expect(services.profile.profile, isNull);
    expect(services.history.items, isEmpty);
    expect(services.history.status, LoadStatus.idle);
  });

  test('demo reset rebuilds the seed and ends any trip', () async {
    await signIn();
    await services.availability.goOnline();
    await waitFor(() => services.offers.offer != null);
    await services.offers.accept();

    services.demo!.resetData();
    await settle();

    expect(services.trip.hasTrip, isFalse);
    expect(services.availability.isOnline, isFalse);
  });
}
