import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/availability.dart';
import 'package:qwiko_delivery_agent/models/media_ref.dart';
import 'package:qwiko_delivery_agent/models/partner.dart';
import 'package:qwiko_delivery_agent/widgets/otp_input.dart';
import 'package:qwiko_delivery_agent/widgets/primary_button.dart';

void main() {
  late FakeClock clock;
  late AppServices services;

  /// Services are built inside the test body so event-driven refreshes run in
  /// the widget test's fake-async zone; built in setUp, they never complete.
  void testHome(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      clock = FakeClock(DateTime(2026, 10, 13, 14));
      services = AppServices.demo(
        clock: clock,
        latency: Duration.zero,
        firstOfferDelay: const Duration(minutes: 30),
        offerInterval: const Duration(minutes: 30),
      );
      addTearDown(services.dispose);
      tester.view.physicalSize = const Size(400, 860) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await body(tester);
    });
  }

  /// The radar repeats forever, so tests run with reduced motion.
  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    reduceMotion(tester);
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
    expect(find.text('Hello, Arjun 👋'), findsOneWidget);
  }

  /// Ends with no timers running: offline, then the app unmounted.
  Future<void> finish(WidgetTester tester) async {
    if (services.availability.isOnline) {
      await services.availability.goOffline();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  Finder onlineSwitch() => find.byType(Switch);

  Future<void> scrollToTop(WidgetTester tester) async {
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 2000),
      3000,
    );
    await tester.pumpAndSettle();
  }

  testHome('Going online shows the waiting state and survives tab switches', (
    tester,
  ) async {
    await signIn(tester);
    expect(find.text('You are Offline'), findsOneWidget);

    await tap(tester, onlineSwitch());
    expect(find.text('You are Online'), findsOneWidget);
    expect(find.text('Looking for orders near you…'), findsOneWidget);
    expect(services.offers.isListening, isTrue);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text('You are Online'), findsOneWidget);

    await finish(tester);
  });

  testHome('A break pauses offers, counts down and ends by itself', (
    tester,
  ) async {
    await signIn(tester);
    await tap(tester, onlineSwitch());
    await tap(tester, find.text('Take a break'));
    await tap(tester, find.text('15 minutes'));

    expect(find.text('You are on a break'), findsOneWidget);
    expect(find.text('Offers paused · 15:00 left'), findsOneWidget);
    expect(services.offers.isListening, isFalse);

    clock.advance(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Offers paused · 10:00 left'), findsOneWidget);

    clock.advance(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('You are Online'), findsOneWidget);
    await scrollToTop(tester);
    expect(
      find.text("Your break is over. You'll receive orders again."),
      findsOneWidget,
    );
    expect(services.offers.isListening, isTrue);

    await finish(tester);
  });

  testHome('Blockers replace the toggle and link to their fixes', (
    tester,
  ) async {
    services.demo!.blockGoingOnline();
    await signIn(tester);

    expect(find.text("You can't go online yet"), findsOneWidget);
    expect(
      find.text('Fix these 2 things to start receiving orders.'),
      findsOneWidget,
    );
    expect(onlineSwitch(), findsNothing);

    await tap(tester, find.text('Deposit cash'));
    expect(find.text('Cash in hand'), findsWidgets);
    await tap(tester, find.widgetWithText(PrimaryButton, 'Deposit cash'));
    expect(find.textContaining('Deposited ₹2,150'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await scrollToTop(tester);

    expect(find.text('Fix this to start receiving orders.'), findsOneWidget);
    await tap(tester, find.text('Upload new'));
    expect(find.text('Documents'), findsWidgets);
    await services.profile.saveDocuments({
      DocumentType.license: const MediaRef.sample('doc-license'),
    });
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text("You can't go online yet"), findsNothing);
    await scrollToTop(tester);
    await tap(tester, onlineSwitch());
    expect(find.text('You are Online'), findsOneWidget);

    await finish(tester);
  });

  testHome('Location blocker is fixed from the simulated prompt', (
    tester,
  ) async {
    services.demo!.locationPermissionGranted = false;
    await signIn(tester);

    await tap(tester, find.text('Allow location'));
    expect(find.text('Simulated system prompt'), findsOneWidget);
    await tap(tester, find.text('While using the app'));
    expect(services.availability.blockers, isEmpty);
    await scrollToTop(tester);
    expect(onlineSwitch(), findsOneWidget);

    await finish(tester);
  });

  testHome('Summary shows a retryable error when loading fails', (
    tester,
  ) async {
    services.demo!.failNext(OperationType.loadEarnings);
    await signIn(tester);

    expect(find.text('Try again'), findsWidgets);
    await tap(tester, find.text('Try again').first);
    expect(find.text('Earnings'), findsWidgets);
    expect(find.text('Acceptance'), findsOneWidget);

    await finish(tester);
  });

  testHome('Summary tiles open their details', (tester) async {
    await signIn(tester);

    await tap(tester, find.text('Acceptance'));
    expect(find.text('Acceptance rate · last 7 days'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tap(tester, find.text('Online').first);
    expect(find.text('Activity'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tap(tester, find.text('Orders').first);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await finish(tester);
  });

  testHome('Demand nudge moves the rider and announcements dismiss', (
    tester,
  ) async {
    await signIn(tester);

    final nudge = find.textContaining('High demand in Connaught Place · 1.3×');
    await tester.scrollUntilVisible(nudge, 200);
    await tap(tester, find.text('Move to zone'));
    expect(services.availability.zoneId, 'cp');
    expect(find.textContaining('High demand in Karol Bagh'), findsOneWidget);

    final rain = find.text('Rain expected from 6 PM');
    await tester.scrollUntilVisible(rain, 200);
    await tap(tester, find.byTooltip('Dismiss Rain expected from 6 PM'));
    expect(rain, findsNothing);

    await finish(tester);
  });

  group('Fits 320 dp at text scale 2.0', () {
    void useSmallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(320, 640) * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    Future<void> scrollThrough(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(
          find.byType(Scrollable).first,
          const Offset(0, -500),
          2000,
        );
        await tester.pumpAndSettle();
      }
    }

    Future<void> visit(WidgetTester tester, String route) async {
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pushNamed(route);
      await tester.pumpAndSettle();
      await scrollThrough(tester);
      navigator.pop();
      await tester.pumpAndSettle();
    }

    testHome('dashboard online, on break and blocked', (tester) async {
      useSmallScreen(tester);
      await signIn(tester);
      await scrollThrough(tester);

      await services.availability.goOnline();
      await tester.pumpAndSettle();
      await scrollThrough(tester);

      await services.availability.startBreak(const Duration(minutes: 30));
      await tester.pumpAndSettle();
      await scrollThrough(tester);
      expect(services.availability.status, AvailabilityStatus.onBreak);

      await services.availability.goOffline();
      services.demo!
        ..blockGoingOnline()
        ..locationPermissionGranted = false;
      await tester.pumpAndSettle();
      await scrollThrough(tester);

      for (final route in [
        '/wallet/cash',
        '/activity',
        '/performance',
        '/demand',
        '/safety',
      ]) {
        await visit(tester, route);
      }
      expect(tester.takeException(), isNull);

      await finish(tester);
    });
  });
}
