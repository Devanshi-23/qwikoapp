import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_routes.dart';
import 'package:qwiko_delivery_agent/app/app_scope.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/app/app_theme.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/models/trip.dart';
import 'package:qwiko_delivery_agent/screens/orders/active_order_screen.dart';
import 'package:qwiko_delivery_agent/widgets/progress_tracker.dart';
import 'package:qwiko_delivery_agent/widgets/slide_to_confirm.dart';

void main() {
  late AppServices services;
  late FakeClock clock;

  /// Services are built in the test body so timers run in fake async, and
  /// disposed at the end so none are left pending.
  void testTrip(
    String description,
    WidgetTesterCallback body, {
    Size size = const Size(400, 860),
    double textScale = 1,
  }) {
    testWidgets(description, (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      services = AppServices.demo(
        clock: clock = FakeClock(DateTime(2026, 10, 13, 14)),
        latency: Duration.zero,
        firstOfferDelay: const Duration(minutes: 30),
        offerInterval: const Duration(minutes: 30),
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      services.dispose();
      await tester.pump(const Duration(seconds: 6));
    });
  }

  Future<void> openActiveOrder(WidgetTester tester) async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.wallet.load();
    await services.availability.goOnline();
    services.demo!.sendOffer(const OfferRequest(payment: PaymentMode.prepaid));
    await tester.pump();
    await services.offers.accept();
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ActiveOrderScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> arrive(WidgetTester tester) async {
    services.demo!.jumpToNextStop();
    await tester.pumpAndSettle();
    await tap(tester, find.text("I've arrived"));
  }

  bool arrivedEnabled(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(
            find.ancestor(
              of: find.text("I've arrived"),
              matching: find.byType(ElevatedButton),
            ),
          )
          .onPressed !=
      null;

  bool slideEnabled(WidgetTester tester) =>
      tester.widget<SlideToConfirm>(find.byType(SlideToConfirm)).enabled;

  testTrip('Happy path: arrive inside 200 m, check items, slide to pick up', (
    tester,
  ) async {
    await openActiveOrder(tester);

    expect(
      tester.widget<ProgressTracker>(find.byType(ProgressTracker)).steps,
      ActiveOrderScreen.progressSteps,
    );
    expect(find.text(services.trip.trip!.store.name), findsWidgets);
    expect(arrivedEnabled(tester), isFalse);
    expect(
      find.textContaining('Available within 200 m of the store · '),
      findsOneWidget,
    );

    services.demo!.jumpToNextStop();
    await tester.pumpAndSettle();
    expect(arrivedEnabled(tester), isTrue);
    await tap(tester, find.text("I've arrived"));

    final trip = services.trip.trip!;
    expect(trip.status, TripStatus.atStore);
    expect(find.text('Pickup code ${trip.pickupCode}'), findsOneWidget);
    expect(find.textContaining('Waiting 0:00'), findsOneWidget);
    expect(slideEnabled(tester), isFalse);
    final count = trip.pickupItems.length;
    expect(
      find.text(
        'Check $count more ${count == 1 ? 'item' : 'items'} to '
        'confirm pickup.',
      ),
      findsOneWidget,
    );

    await tap(tester, find.text('Mark all as checked'));
    expect(slideEnabled(tester), isTrue);
    expect(find.text('Check items · $count of $count'), findsOneWidget);

    await tester.ensureVisible(find.byType(SlideToConfirm));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SlideToConfirm), const Offset(900, 0));
    await tester.pumpAndSettle();

    expect(services.trip.trip!.status, TripStatus.inProgress);
    expect(find.textContaining('Picked up. Head to'), findsOneWidget);
    expect(find.text('Deliver to customer'), findsOneWidget);
  });

  testTrip('Waiting pay shows after 5 minutes at the store', (tester) async {
    await openActiveOrder(tester);
    await arrive(tester);
    expect(find.textContaining('Waiting pay starts in'), findsOneWidget);

    clock.advance(const Duration(minutes: 6, seconds: 5));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Waiting 6:05'), findsOneWidget);
    expect(
      find.textContaining('Waiting pay is now being added (₹1/min)'),
      findsOneWidget,
    );
  });

  testTrip('Item missing: remove it from the order', (tester) async {
    await openActiveOrder(tester);
    await arrive(tester);
    final item = services.trip.trip!.tasks.first.items.first;

    await tap(tester, find.text('Store issue'));
    expect(find.text('Report a store issue'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    await tap(
      tester,
      find.descendant(of: sheet, matching: find.text('Item missing')),
    );
    await tap(
      tester,
      find.descendant(of: sheet, matching: find.text(item.label)),
    );
    await tap(
      tester,
      find.descendant(of: sheet, matching: find.text('Remove from order')),
    );
    await tap(
      tester,
      find.descendant(of: sheet, matching: find.text('Report issue')),
    );

    expect(find.textContaining('Removed 1 item'), findsOneWidget);
    expect(find.text('Removed from the order'), findsOneWidget);
    expect(
      services.trip.trip!.tasks.first.items.first.status,
      ItemStatus.removed,
    );
  });

  testTrip('Store issues that need arrival are disabled on the way', (
    tester,
  ) async {
    await openActiveOrder(tester);

    await tap(tester, find.text('Report a store issue'));
    expect(
      find.text('Available within 200 m of the store'),
      findsOneWidget,
      reason: 'store closed needs the geofence',
    );
    expect(find.textContaining('Available after you tap'), findsWidgets);
  });

  testTrip('Customer cancels: reason, no pay under 500 m, back Home', (
    tester,
  ) async {
    await openActiveOrder(tester);

    services.demo!.cancelTrip(CancelledBy.customer);
    await tester.pumpAndSettle();

    expect(find.text('Order cancelled'), findsOneWidget);
    expect(find.text('The customer cancelled the order.'), findsOneWidget);
    expect(find.textContaining('No compensation'), findsOneWidget);
    await tap(tester, find.text('Back to Home'));

    expect(services.trip.hasTrip, isFalse);
    expect(find.text('No active order right now.'), findsOneWidget);
  });

  testTrip('Cancelled at the store: ₹15 plus waiting, then leave', (
    tester,
  ) async {
    await openActiveOrder(tester);
    await arrive(tester);
    clock.advance(const Duration(minutes: 7));

    services.demo!.cancelTrip(CancelledBy.store);
    await tester.pumpAndSettle();

    expect(find.text('For your trip to the store'), findsOneWidget);
    expect(find.text('₹15'), findsOneWidget);
    expect(find.text('Waiting pay'), findsOneWidget);
    await tap(tester, find.text("I'm leaving the store"));
    expect(services.trip.hasTrip, isFalse);
  });

  testTrip('Offline arrival shows "Will sync when online"', (tester) async {
    await openActiveOrder(tester);
    services.demo!.networkAvailable = false;
    await arrive(tester);

    expect(find.text('Will sync when online'), findsOneWidget);
    services.demo!.networkAvailable = true;
    await tester.pumpAndSettle();
    expect(find.text('Will sync when online'), findsNothing);
  });

  for (final (name, size, scale) in [
    ('320 dp at text scale 2.0', const Size(320, 640), 2.0),
    ('landscape', const Size(640, 320), 1.0),
  ]) {
    testTrip(
      'Pickup screens fit $name',
      (tester) async {
        await openActiveOrder(tester);
        expect(tester.takeException(), isNull);

        await arrive(tester);
        expect(tester.takeException(), isNull);

        await tap(tester, find.text('Store issue'));
        await tap(tester, find.text('Item damaged').last);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        services.demo!.cancelTrip(CancelledBy.store);
        await tester.pumpAndSettle();
        expect(find.text("I'm leaving the store"), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: size,
      textScale: scale,
    );
  }
}
