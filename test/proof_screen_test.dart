import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_routes.dart';
import 'package:qwiko_delivery_agent/app/app_scope.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/app/app_theme.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/formatters.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/delivery_check.dart';
import 'package:qwiko_delivery_agent/models/money.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/screens/orders/active_order_screen.dart';
import 'package:qwiko_delivery_agent/screens/orders/delivery_complete_screen.dart';
import 'package:qwiko_delivery_agent/screens/orders/proof_of_delivery_screen.dart';
import 'package:qwiko_delivery_agent/widgets/otp_input.dart';
import 'package:qwiko_delivery_agent/widgets/slide_to_confirm.dart';

void main() {
  late AppServices services;
  late FakeClock clock;

  void testProof(
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
      await tester.pump(const Duration(seconds: 11));
    });
  }

  /// Opens the proof screen for a drop the rider has arrived at.
  Future<DeliveryTask> openProof(
    WidgetTester tester, {
    PaymentMode payment = PaymentMode.prepaid,
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
          home: const Scaffold(body: Text('Home')),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const ActiveOrderScreen()),
    );
    await tester.pumpAndSettle();
    services.demo!.jumpToNextStop();
    await services.trip.arrivedAtStore();
    await services.trip.checkAllItems();
    await services.trip.pickedUp();
    await tester.pumpAndSettle();
    services.demo!.jumpToNextStop();
    await services.trip.arrivedAtCustomer();
    await tester.pumpAndSettle();
    await tap(tester, find.text('Complete Delivery'));
    expect(find.byType(ProofOfDeliveryScreen), findsOneWidget);
    return services.trip.currentTask!;
  }

  bool slideEnabled(WidgetTester tester) =>
      tester.widget<SlideToConfirm>(find.byType(SlideToConfirm)).enabled;

  Finder otpField() => find.descendant(
    of: find.byType(OtpInput),
    matching: find.byType(EditableText),
  );

  Future<void> enterOtp(WidgetTester tester, String code) async {
    await tester.ensureVisible(find.byType(OtpInput));
    await tester.enterText(otpField(), code);
    await tester.pumpAndSettle();
  }

  Future<void> addSamplePhoto(WidgetTester tester) async {
    await tap(tester, find.text('Add photo'));
    await tap(tester, find.text('Use sample photo'));
  }

  Future<void> slide(WidgetTester tester) async {
    await tester.drag(find.byType(SlideToConfirm), const Offset(900, 0));
    await tester.pumpAndSettle();
  }

  testProof('OTP lockout, then proof and a completion summary', (tester) async {
    final task = await openProof(tester);
    final method = task.requiredProof;

    expect(slideEnabled(tester), isFalse);
    expect(find.textContaining('Still needed:'), findsOneWidget);

    if (method.needsOtp) {
      final right = services.demo!.customerOtp!;
      expect(find.text('Demo: the code is $right'), findsOneWidget);
      final wrong = right == '1111' ? '2222' : '1111';
      await enterOtp(tester, wrong);
      expect(find.text('Wrong code. 2 tries left.'), findsOneWidget);
      await enterOtp(tester, wrong);
      await enterOtp(tester, wrong);
      expect(find.textContaining('Too many wrong codes'), findsOneWidget);

      clock.advance(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      await enterOtp(tester, right);
      expect(find.text('OTP verified'), findsWidgets);
    }
    if (method.needsPhoto) await addSamplePhoto(tester);

    expect(slideEnabled(tester), isTrue);
    await slide(tester);

    expect(find.byType(DeliveryCompleteScreen), findsOneWidget);
    expect(find.text('Delivered!'), findsOneWidget);
    expect(
      find.text('You earned ${formatPaise(services.trip.tripEarnedPaise)}'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await services.earnings.fetch();
    expect(
      services.earnings.entries.where(
        (e) => e.type == EarningType.tip && e.orderId == task.orderId,
      ),
      hasLength(1),
    );

    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testProof('COD: change, short amount and the rest by UPI', (tester) async {
    final task = await openProof(tester, payment: PaymentMode.cod);
    if (task.requiredProof.needsOtp) {
      await enterOtp(tester, services.demo!.customerOtp!);
    }
    if (task.requiredProof.needsPhoto) await addSamplePhoto(tester);
    final due = task.payment.amountToCollectPaise ~/ 100;

    final cashField = find.widgetWithText(TextField, 'Cash received (₹)');
    await tester.ensureVisible(cashField);
    await tester.enterText(cashField, '${due + 50}');
    await tester.pumpAndSettle();
    expect(find.text('Return ₹50 change.'), findsOneWidget);
    expect(slideEnabled(tester), isTrue);

    await tester.enterText(cashField, '${due - 20}');
    await tester.pumpAndSettle();
    expect(find.textContaining('₹20 short'), findsOneWidget);
    expect(slideEnabled(tester), isFalse);

    await tap(tester, find.text('Customer pays the rest by UPI'));
    expect(find.text('Demo QR · not payable'), findsOneWidget);
    services.demo!.upiPaymentFails = true;
    await tap(tester, find.text('Check payment'));
    expect(find.textContaining('Payment failed'), findsOneWidget);
    services.demo!.upiPaymentFails = false;
    await tap(tester, find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('₹20 received by UPI'), findsOneWidget);
    expect(slideEnabled(tester), isTrue);
    await tester.ensureVisible(find.byType(SlideToConfirm));
    await slide(tester);
    expect(find.byType(DeliveryCompleteScreen), findsOneWidget);
    expect(find.textContaining('cash + ₹20 UPI'), findsOneWidget);
  });

  testProof(
    'Proof screen fits 320 dp at text scale 2.0',
    (tester) async {
      await openProof(tester, payment: PaymentMode.cod);
      expect(tester.takeException(), isNull);
    },
    size: const Size(320, 640),
    textScale: 2,
  );
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
