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
import 'package:qwiko_delivery_agent/screens/orders/chat_screen.dart';

void main() {
  late AppServices services;
  late FakeClock clock;

  void testDelivery(
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

  /// Opens the active order already picked up and heading to the customer.
  Future<void> openPickedUp(
    WidgetTester tester, {
    PaymentMode payment = PaymentMode.cod,
  }) async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.wallet.load();
    await services.availability.goOnline();
    services.demo!.sendOffer(OfferRequest(payment: payment));
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
    services.demo!.jumpToNextStop();
    await services.trip.arrivedAtStore();
    await services.trip.checkAllItems();
    await services.trip.pickedUp();
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<ButtonStyleButton>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.bySubtype<ButtonStyleButton>(),
                )
                .first,
          )
          .onPressed !=
      null;

  testDelivery('Heading to the customer: details, COD and the 100 m rule', (
    tester,
  ) async {
    await openPickedUp(tester);
    final task = services.trip.trip!.currentTask;

    expect(find.text('Deliver to customer'), findsOneWidget);
    expect(find.text(task.customer.firstName), findsOneWidget);
    expect(find.textContaining('Cash on delivery: collect'), findsOneWidget);
    expect(enabled(tester, "I've arrived"), isFalse);
    expect(
      find.textContaining('Available within 100 m of the customer'),
      findsOneWidget,
    );

    services.demo!.jumpToNextStop();
    await tester.pumpAndSettle();
    expect(enabled(tester, "I've arrived"), isTrue);
    await tap(tester, find.text("I've arrived"));

    expect(
      services.trip.trip!.currentTask.status,
      OrderStatus.arrivedAtCustomer,
    );
    expect(find.text('Hand over the order'), findsOneWidget);
    expect(find.text('Calls: 0 of 2'), findsOneWidget);
    expect(enabled(tester, 'Mark undeliverable'), isFalse);
    expect(
      find.text('Call the customer 2 more times and wait 5:00 more.'),
      findsOneWidget,
    );
  });

  testDelivery('Simulated call: connecting, ringing, then the result', (
    tester,
  ) async {
    await openPickedUp(tester);
    services.demo!.customerResponse = CustomerResponse.noAnswer;
    await tap(tester, find.text('Call'));

    expect(find.text('Connecting via Qwiko number…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ringing…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.text('No answer. The attempt is logged on the order.'),
      findsOneWidget,
    );
    expect(services.trip.trip!.currentTask.callAttempts, 1);

    await tap(tester, find.text('Done'));
    expect(find.text('Connecting via Qwiko number…'), findsNothing);
  });

  testDelivery('After calls and the wait, undeliverable starts the return', (
    tester,
  ) async {
    await openPickedUp(tester);
    services.demo!.jumpToNextStop();
    await services.trip.arrivedAtCustomer();
    services.demo!.customerResponse = CustomerResponse.noAnswer;
    await services.trip.callCustomer();
    await services.trip.callCustomer();
    clock.advance(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Calls: 2 of 2'), findsOneWidget);
    expect(enabled(tester, 'Mark undeliverable'), isTrue);
    expect(find.textContaining("You've called and waited."), findsOneWidget);

    final task = services.trip.trip!.currentTask;
    await tap(tester, find.text('Mark undeliverable'));
    final confirm = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Mark undeliverable'),
    );
    expect(find.text('Choose a reason first.'), findsOneWidget);
    await tap(tester, find.text("Customer isn't answering calls"));
    await tap(tester, confirm.last);

    if (task.isReturnable) {
      expect(services.trip.trip!.status, TripStatus.returningToStore);
      expect(
        find.text('Return ${task.displayId} to the store'),
        findsOneWidget,
      );
      expect(find.text('Returned to store'), findsOneWidget);
    } else {
      expect(find.text('Keep or dispose as instructed'), findsOneWidget);
      await tap(tester, find.text('OK'));
      expect(services.trip.trip, isNull);
    }
  });

  testDelivery('Chat: quick replies, ticks and the simulated label', (
    tester,
  ) async {
    await openPickedUp(tester);
    await tap(tester, find.text('Chat'));

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.textContaining('Simulated chat'), findsOneWidget);
    for (final reply in ChatScreen.quickReplies.take(2)) {
      expect(find.text(reply), findsOneWidget);
    }

    await tap(tester, find.widgetWithText(ActionChip, 'On my way'));
    expect(find.text('On my way'), findsNWidgets(2));
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      services.trip.trip!.currentTask.chat.last.type,
      OrderEventType.chatReceived,
    );
  });

  for (final (name, size) in [
    ('320 dp at text scale 2.0', const Size(320, 640)),
    ('landscape', const Size(800, 400)),
  ]) {
    testDelivery(
      'At the customer fits $name',
      (tester) async {
        await openPickedUp(tester);
        services.demo!.jumpToNextStop();
        await services.trip.arrivedAtCustomer();
        await tester.pumpAndSettle();
        expect(find.text('Mark undeliverable'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: size,
      textScale: size.width == 320 ? 2 : 1,
    );
  }
}
