import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/controllers/demo_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/activity.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/screens/offers/offer_sheet.dart';
import 'package:qwiko_delivery_agent/screens/orders/active_order_screen.dart';
import 'package:qwiko_delivery_agent/widgets/otp_input.dart';
import 'package:qwiko_delivery_agent/widgets/slide_to_confirm.dart';

void main() {
  late FakeClock clock;
  late AppServices services;

  /// Services are built inside the test body so their timers and event
  /// refreshes run in the widget test's fake-async zone, and disposed at the
  /// end so no timers are left pending.
  void testOffer(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      clock = FakeClock(DateTime(2026, 10, 13, 14));
      services = AppServices.demo(
        clock: clock,
        latency: Duration.zero,
        firstOfferDelay: const Duration(minutes: 30),
        offerInterval: const Duration(minutes: 30),
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(400, 860) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      services.dispose();
      await tester.pump(const Duration(seconds: 6));
    });
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> signInAndGoOnline(WidgetTester tester) async {
    await tester.pumpWidget(QwikoApp(services: services));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Get started'));
    await tester.enterText(find.byType(TextFormField).first, '9123456780');
    await tap(tester, find.text('Continue with phone'));
    await tester.enterText(
      find.descendant(
        of: find.byType(OtpInput),
        matching: find.byType(TextField),
      ),
      '123456',
    );
    await tester.pumpAndSettle();
    await services.availability.goOnline();
    await tester.pumpAndSettle();
  }

  Future<void> sendOffer(
    WidgetTester tester, [
    OfferRequest request = const OfferRequest(),
  ]) async {
    expect(services.demo!.sendOffer(request), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(OfferSheet), findsOneWidget);
  }

  Future<void> slideToAccept(WidgetTester tester) async {
    await tester.drag(find.byType(SlideToConfirm), const Offset(900, 0));
    await tester.pumpAndSettle();
  }

  int count(ActivityType type) =>
      services.availability.recentEvents.where((e) => e.type == type).length;

  testOffer('Offer opens over any tab; a tap never accepts; sliding does', (
    tester,
  ) async {
    await signInAndGoOnline(tester);
    await tap(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Earnings'),
      ),
    );
    await sendOffer(tester);
    expect(find.text('Slide to accept'), findsOneWidget);
    expect(find.text('Full address after you accept'), findsOneWidget);

    await tester.tap(find.byType(SlideToConfirm));
    await tester.pumpAndSettle();
    expect(services.trip.hasTrip, isFalse);
    expect(find.byType(OfferSheet), findsOneWidget);

    await slideToAccept(tester);
    expect(services.trip.hasTrip, isTrue);
    expect(find.byType(OfferSheet), findsNothing);
    expect(find.byType(ActiveOrderScreen), findsOneWidget);
  });

  testOffer('Back opens the reasons, back again returns, decline logs', (
    tester,
  ) async {
    await signInAndGoOnline(tester);
    final declined = count(ActivityType.offerDeclined);
    await sendOffer(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Why are you declining?'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Why are you declining?'), findsNothing);
    expect(find.text('Slide to accept'), findsOneWidget);
    expect(services.offers.offer, isNotNull);

    await tap(tester, find.text('Decline'));
    await tap(tester, find.text('Too far'));
    await tap(tester, find.text('Decline order'));

    expect(find.byType(OfferSheet), findsNothing);
    expect(find.text('Offer declined.'), findsOneWidget);
    expect(count(ActivityType.offerDeclined), declined + 1);
    expect(
      services.availability.recentEvents
          .firstWhere((e) => e.type == ActivityType.offerDeclined)
          .details,
      endsWith('Too far'),
    );
  });

  testOffer('Closing an offer can decline it and take the rider offline', (
    tester,
  ) async {
    await signInAndGoOnline(tester);
    await sendOffer(tester);

    await tap(tester, find.byTooltip('Not now'));
    expect(find.text('Why are you declining?'), findsOneWidget);
    expect(find.text('Choose a reason first.'), findsOneWidget);
    await tap(tester, find.text('Going offline soon'));
    await tap(tester, find.text('Decline and go offline'));

    expect(find.byType(OfferSheet), findsNothing);
    expect(services.offers.offer, isNull);
    expect(services.availability.isOnline, isFalse);
    expect(
      find.text("Offer declined. You're offline and won't get new orders."),
      findsOneWidget,
    );
    expect(find.text('Hello, Arjun 👋'), findsOneWidget);

    expect(services.demo!.sendOffer(const OfferRequest()), isFalse);
  });

  testOffer('A timed-out offer closes with the missed message', (tester) async {
    await signInAndGoOnline(tester);
    final missed = count(ActivityType.offerMissed);
    await sendOffer(tester, const OfferRequest(timeoutSeconds: 5));

    clock.advance(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(OfferSheet), findsNothing);
    expect(find.textContaining('Offer missed.'), findsOneWidget);
    expect(count(ActivityType.offerMissed), missed + 1);
  });

  testOffer('An offer taken by someone else shows a notice', (tester) async {
    await signInAndGoOnline(tester);
    services.demo!.takeNextOffer = true;
    await sendOffer(tester);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('This order is no longer available'), findsOneWidget);
    expect(find.text('Slide to accept'), findsNothing);

    await tap(tester, find.text('Dismiss'));
    expect(find.byType(OfferSheet), findsNothing);
    expect(services.offers.offer, isNull);
  });

  testOffer('Cash near the limit disables accepting a COD offer', (
    tester,
  ) async {
    await signInAndGoOnline(tester);
    services.demo!.setCashInHand(DemoController.nearLimitCashPaise);
    await tester.pumpAndSettle();
    await sendOffer(tester, const OfferRequest(payment: PaymentMode.cod));

    expect(
      find.text('Deposit cash to accept COD orders above ₹150.'),
      findsNWidgets(2),
    );
    expect(
      tester.widget<SlideToConfirm>(find.byType(SlideToConfirm)).enabled,
      isFalse,
    );
    await slideToAccept(tester);
    expect(services.trip.hasTrip, isFalse);
  });

  testOffer('Batched COD offer fits 320 dp at text scale 2.0', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await signInAndGoOnline(tester);
    services.demo!.setCashInHand(DemoController.nearLimitCashPaise);
    await tester.pumpAndSettle();
    await sendOffer(
      tester,
      const OfferRequest(batched: true, payment: PaymentMode.cod),
    );
    await tap(tester, find.text('Pay breakdown'));
    for (var i = 0; i < 6; i++) {
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -400),
        2000,
      );
      await tester.pumpAndSettle();
    }
    await tap(tester, find.text('Decline'));
    await tap(tester, find.text('Other'));
    expect(find.text('Note (optional)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
