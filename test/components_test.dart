import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_scope.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/app/app_theme.dart';
import 'package:qwiko_delivery_agent/app/gallery_samples.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/models/money.dart';
import 'package:qwiko_delivery_agent/screens/demo/component_gallery_screen.dart';
import 'package:qwiko_delivery_agent/widgets/app_scaffold.dart';
import 'package:qwiko_delivery_agent/widgets/countdown_ring.dart';
import 'package:qwiko_delivery_agent/widgets/dialogs.dart';
import 'package:qwiko_delivery_agent/widgets/money_text.dart';
import 'package:qwiko_delivery_agent/widgets/otp_input.dart';
import 'package:qwiko_delivery_agent/widgets/progress_tracker.dart';
import 'package:qwiko_delivery_agent/widgets/slide_to_confirm.dart';
import 'package:qwiko_delivery_agent/widgets/status_badge.dart';

final DateTime _now = DateTime(2026, 10, 13, 14);

Widget _host(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  group('SlideToConfirm', () {
    late int confirmed;

    Widget slider({bool enabled = true}) => _host(
      SlideToConfirm(
        label: 'Slide to accept',
        enabled: enabled,
        onConfirmed: () => confirmed++,
      ),
    );

    setUp(() => confirmed = 0);

    testWidgets('confirms when dragged to the end', (tester) async {
      await tester.pumpWidget(slider());
      await tester.drag(find.byType(SlideToConfirm), const Offset(800, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
    });

    testWidgets('springs back on a short drag', (tester) async {
      await tester.pumpWidget(slider());
      await tester.drag(find.byType(SlideToConfirm), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
    });

    testWidgets('confirms after press and hold', (tester) async {
      await tester.pumpWidget(slider());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SlideToConfirm)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 1300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(confirmed, 1);
    });

    testWidgets('releasing a hold early cancels', (tester) async {
      await tester.pumpWidget(slider());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SlideToConfirm)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(confirmed, 0);
    });

    testWidgets('screen readers confirm with the tap action', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(slider());
      tester.semantics.tap(find.semantics.byLabel('Slide to accept'));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      handle.dispose();
    });

    testWidgets('does nothing while disabled', (tester) async {
      await tester.pumpWidget(slider(enabled: false));
      await tester.drag(find.byType(SlideToConfirm), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
    });
  });

  testWidgets('OtpInput keeps digits only and reports completion', (
    tester,
  ) async {
    String? completed;
    await tester.pumpWidget(
      _host(OtpInput(onCompleted: (value) => completed = value)),
    );

    await tester.enterText(find.byType(TextField), '12ab');
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(completed, isNull);

    await tester.enterText(find.byType(TextField), '1234567');
    await tester.pump();
    expect(completed, '123456');
    expect(find.text('7'), findsNothing);
  });

  testWidgets('MoneyText and StatusBadge read well to screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const MoneyText(129500),
            StatusBadge.payout(PayoutStatus.failed),
            const CountdownRing(
              remaining: Duration(milliseconds: 3200),
              total: Duration(seconds: 30),
            ),
            const ProgressTracker(
              steps: ['Pickup', 'Collect', 'Drop', 'Deliver'],
              current: 1,
            ),
          ],
        ),
      ),
    );

    expect(find.text('₹1,295'), findsOneWidget);
    expect(find.bySemanticsLabel('1,295 rupees'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Status: Failed'), findsOneWidget);
    expect(find.bySemanticsLabel('4 seconds left'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 2 of 4: Collect'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('showConfirmDialog returns the choice', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showConfirmDialog(
                context,
                title: 'Log out?',
                message: 'You will need to log in again.',
                confirmLabel: 'Log out',
                destructive: true,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(results, [true, false]);
  });

  testWidgets('AppScaffold shows the banner while the demo is offline', (
    tester,
  ) async {
    final services = AppServices.demo(
      clock: FakeClock(_now),
      latency: Duration.zero,
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          home: AppScaffold(title: 'Test', body: const SizedBox()),
        ),
      ),
    );
    expect(find.textContaining("You're offline"), findsNothing);

    services.demo!.networkAvailable = false;
    await tester.pump();
    expect(find.textContaining("You're offline"), findsOneWidget);

    services.demo!.networkAvailable = true;
    await tester.pump();
    expect(find.textContaining("You're offline"), findsNothing);
  });

  group('Component gallery', () {
    final samples = GallerySamples.fromSeed(_now);

    for (final scale in [1.0, 2.0]) {
      testWidgets('renders every component at 320 dp, text scale $scale', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(320, 640) * 3
          ..devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: ComponentGalleryScreen(
              samples: samples,
              initialTextScale: scale,
            ),
          ),
        );
        await tester.pump();

        expect(samples.orders, hasLength(3));
        expect(find.byType(SlideToConfirm), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
