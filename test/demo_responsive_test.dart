import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app.dart';
import 'package:qwiko_delivery_agent/app/app_routes.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/controllers/demo_controller.dart';
import 'package:qwiko_delivery_agent/controllers/demo_scenarios.dart';
import 'package:qwiko_delivery_agent/controllers/loadable_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/availability.dart';
import 'package:qwiko_delivery_agent/screens/orders/order_details_screen.dart';
import 'package:qwiko_delivery_agent/widgets/order_card.dart';
import 'package:qwiko_delivery_agent/widgets/otp_input.dart';

void main() {
  late AppServices services;

  AppServices build() => AppServices.demo(
    clock: FakeClock(DateTime(2026, 10, 13, 14)),
    latency: Duration.zero,
    firstOfferDelay: const Duration(minutes: 30),
    offerInterval: const Duration(minutes: 30),
  );

  DemoController demo() => services.demo!;

  group('Demo scenarios', () {
    setUp(() async {
      services = build();
      await services.session.signInWithEmail(
        email: 'arjun@example.com',
        password: 'password123',
      );
    });

    tearDown(() => services.dispose());

    test('all 26 scenarios are numbered and scripted', () {
      expect(DemoScenario.values, hasLength(26));
      expect(DemoScenario.values.map((s) => s.number), [
        for (var i = 1; i <= 26; i++) i,
      ]);
      for (final scenario in DemoScenario.values) {
        expect(scenario.title, isNotEmpty);
        expect(scenario.setup, isNotEmpty);
        expect(
          scenario.steps.length,
          greaterThanOrEqualTo(2),
          reason: scenario.title,
        );
      }
      expect(
        DemoScenario.values.map((s) => s.title).toSet(),
        hasLength(DemoScenario.values.length),
      );
    });

    test('running a scenario resets data and applies its setup', () async {
      demo().runScenario(DemoScenario.blockedOnline);
      await services.wallet.load();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(demo().scenario, DemoScenario.blockedOnline);
      expect(services.availability.blockers.map((b) => b.type), [
        OnlineBlockerType.documentExpired,
        OnlineBlockerType.cashLimitReached,
      ]);

      demo().runScenario(DemoScenario.payoutFailure);
      expect(demo().payoutFails, isTrue);
      expect(DemoScenario.payoutFailure.usesTrip, isFalse);

      demo().runScenario(DemoScenario.happyPath);
      expect(demo().payoutFails, isFalse);
      expect(DemoScenario.happyPath.usesTrip, isTrue);

      demo().runScenario(DemoScenario.customerUnreachable);
      expect(demo().customerResponse, CustomerResponse.noAnswer);

      demo().resetData();
      expect(demo().scenario, isNull);
      expect(demo().customerResponse, isNot(CustomerResponse.noAnswer));
    });

    test('"Next request fails" fails exactly one server call', () async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      demo().failNextRequest();
      await services.wallet.load();
      expect(services.wallet.status, LoadStatus.error);
      await services.wallet.load();
      expect(services.wallet.isReady, isTrue);
    });
  });

  void testApp(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      services = build();
      addTearDown(services.dispose);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await body(tester);
    });
  }

  void useSize(WidgetTester tester, Size size, {double textScale = 1}) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.pumpWidget(QwikoApp(services: services));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '9123456780');
    await tester.ensureVisible(find.text('Continue with phone'));
    await tester.tap(find.text('Continue with phone'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(OtpInput),
        matching: find.byType(TextField),
      ),
      '123456',
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    if (services.availability.isOnline) {
      await services.availability.goOffline();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  testApp('wide screens use a rail and list-detail panes', (tester) async {
    useSize(tester, const Size(1200, 800));
    await signIn(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Orders'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Select an order'), findsOneWidget);

    await tester.tap(find.byType(OrderCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Select an order'), findsNothing);
    expect(find.byType(OrderDetailsScreen), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Earnings'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pushNamed(AppRoutes.notifications);
    await tester.pumpAndSettle();
    expect(find.text('Select a notification'), findsOneWidget);

    await finish(tester);
  });

  testApp('phones keep the bottom navigation bar', (tester) async {
    useSize(tester, const Size(400, 860));
    await signIn(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await finish(tester);
  });

  testApp('new screens fit 320 dp at text scale 2.0', (tester) async {
    useSize(tester, const Size(320, 640), textScale: 2);
    await signIn(tester);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );

    for (final route in [
      AppRoutes.notifications,
      AppRoutes.settings,
      AppRoutes.help,
      AppRoutes.safety,
      AppRoutes.reportIncident,
      AppRoutes.emergencyContacts,
      AppRoutes.ratings,
      AppRoutes.payouts,
      AppRoutes.incentives,
      AppRoutes.demoControls,
    ]) {
      navigator.pushNamed(route);
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.fling(
          find.byType(Scrollable).last,
          const Offset(0, -500),
          2000,
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: route);
      navigator.pop();
      await tester.pumpAndSettle();
    }

    await finish(tester);
  });
}
