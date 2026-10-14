import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_routes.dart';
import 'package:qwiko_delivery_agent/app/app_scope.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/app/app_theme.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/screens/navigation/navigation_screen.dart';
import 'package:qwiko_delivery_agent/screens/navigation/route_widgets.dart';
import 'package:qwiko_delivery_agent/screens/orders/active_order_screen.dart';
import 'package:qwiko_delivery_agent/services/maps/mock_map_view.dart';

void main() {
  late AppServices services;

  /// Services are built in the test body so timers run in fake async, and
  /// disposed at the end so none are left pending.
  void testTrip(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      services = AppServices.demo(
        clock: FakeClock(DateTime(2026, 10, 13, 14)),
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

  Future<void> openActiveOrder(
    WidgetTester tester, {
    bool failRoute = false,
  }) async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.wallet.load();
    await services.availability.goOnline();
    if (failRoute) services.demo!.failNext(OperationType.planRoute);
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

  testTrip('Active order shows the demo map, route and map controls', (
    tester,
  ) async {
    await openActiveOrder(tester);

    expect(find.byType(MockMapView), findsOneWidget);
    expect(find.text(MockMapView.watermark), findsOneWidget);
    expect(find.byTooltip('Recenter'), findsOneWidget);
    expect(find.byTooltip('Show full route'), findsOneWidget);
    expect(find.textContaining('Arrive by'), findsWidgets);
    expect(find.textContaining('demo route'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Map. Route to ')), findsOneWidget);

    final map = tester.getRect(find.byType(MockMapView));
    expect(
      map.height,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
      reason: 'the map fills the screen height beside the landscape panel',
    );
    expect(map.contains(tester.getCenter(find.byTooltip('Recenter'))), isTrue);
    await tester.tap(find.byTooltip('Recenter'));
    await tester.tap(find.byTooltip('Show full route'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testTrip('The route chip lists the directions as text', (tester) async {
    await openActiveOrder(tester);
    final store = services.trip.trip!.store.name;

    await tap(tester, find.byType(RouteChip));

    expect(find.text('Directions to $store'), findsOneWidget);
    expect(find.textContaining('Head '), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining(RegExp('^Destination ')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining(RegExp('^Destination ')), findsOneWidget);
  });

  testTrip('Navigate opens turn-by-turn; mute and end navigation work', (
    tester,
  ) async {
    await openActiveOrder(tester);

    await tap(tester, find.text('Navigate'));
    expect(find.byType(NavigationScreen), findsOneWidget);
    expect(find.textContaining(RegExp(r'^In \d')), findsOneWidget);
    expect(
      find.textContaining(RegExp('^Turn (left|right) onto ')),
      findsWidgets,
    );
    expect(find.textContaining('Arrive by'), findsOneWidget);

    await tap(tester, find.byTooltip('Mute cues'));
    expect(services.navigation.muted, isTrue);
    expect(find.byTooltip('Unmute cues'), findsOneWidget);

    services.demo!.jumpToNextStop();
    await tester.pumpAndSettle();
    expect(find.text('You have arrived'), findsOneWidget);

    await tap(tester, find.text('End navigation'));
    expect(find.byType(NavigationScreen), findsNothing);
    expect(find.byType(ActiveOrderScreen), findsOneWidget);
  });

  testTrip('GPS loss and location settings show banners with fixes', (
    tester,
  ) async {
    await openActiveOrder(tester);
    final demo = services.demo!;

    demo.loseGps();
    await tester.pumpAndSettle();
    expect(find.textContaining('GPS signal lost'), findsOneWidget);

    demo.locationPermissionGranted = false;
    await tester.pumpAndSettle();
    expect(find.textContaining('Location access is off'), findsOneWidget);
    await tap(tester, find.text('Open settings'));
    expect(demo.locationPermissionGranted, isTrue);

    demo.locationServiceEnabled = false;
    await tester.pumpAndSettle();
    await tap(tester, find.text('Turn on'));
    expect(demo.locationServiceEnabled, isTrue);
  });

  testTrip('A routing failure shows the straight-line estimate and Retry', (
    tester,
  ) async {
    await openActiveOrder(tester, failRoute: true);

    expect(
      find.text('Route unavailable · straight-line estimate'),
      findsOneWidget,
    );
    await tap(tester, find.text('Retry'));
    expect(find.textContaining('demo route'), findsOneWidget);
  });

  for (final (name, size) in [
    ('320 dp at text scale 2.0', const Size(320, 640)),
    ('landscape', const Size(640, 320)),
  ]) {
    testTrip('Active order and navigation fit $name', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      if (size.width == 320) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
      }
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openActiveOrder(tester);
      expect(tester.takeException(), isNull);

      await tap(tester, find.text('Navigate'));
      expect(find.byType(NavigationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
