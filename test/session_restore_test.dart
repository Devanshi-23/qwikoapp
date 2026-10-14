import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/data/repositories/session_store.dart';
import 'package:qwiko_delivery_agent/models/auth.dart';
import 'package:qwiko_delivery_agent/services/storage/prefs_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late MemorySessionStore store;
  final opened = <AppServices>[];

  /// A fresh app launch: new services (and demo data) over the same store.
  AppServices launch() {
    final services = AppServices.demo(
      clock: FakeClock(DateTime(2026, 10, 13, 14)),
      latency: Duration.zero,
      firstOfferDelay: const Duration(minutes: 30),
      offerInterval: const Duration(minutes: 30),
      sessionStore: store,
    );
    opened.add(services);
    return services;
  }

  setUp(() => store = MemorySessionStore());

  tearDown(() {
    for (final services in opened) {
      services.dispose();
    }
    opened.clear();
  });

  Future<void> signIn(AppServices services) async {
    await services.session.requestOtp('9123456780', OtpPurpose.signIn);
    await services.session.verifySignInOtp('123456');
  }

  test('signing in is remembered and restores without the network', () async {
    await signIn(launch());
    expect(await store.read(), isNotNull);

    final next = launch();
    next.demo!.networkAvailable = false;
    await expectLater(
      next.session.requestOtp('9123456780', OtpPurpose.signIn),
      throwsA(isA<NetworkUnavailableFailure>()),
    );

    expect(await next.session.restore(), isTrue);
    expect(next.session.isSignedIn, isTrue);
    expect(next.session.partner?.name, startsWith('Arjun'));
  });

  test('logging out forgets the saved session', () async {
    final services = launch();
    await signIn(services);
    await services.session.signOut();
    expect(await store.read(), isNull);

    expect(await launch().session.restore(), isFalse);
  });

  test('a saved session for an unknown account is dropped', () async {
    store = MemorySessionStore(const SavedSession(partnerId: 'P-gone'));
    final services = launch();
    expect(await services.session.restore(), isFalse);
    expect(services.session.isSignedIn, isFalse);
    expect(await store.read(), isNull);
  });

  test('device storage round-trips and ignores corrupt data', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = PrefsSessionStore();
    expect(await prefs.read(), isNull);

    await prefs.write(const SavedSession(partnerId: 'P-1'));
    expect((await prefs.read())?.partnerId, 'P-1');

    await SharedPreferencesAsync().setString(PrefsSessionStore.key, '{oops');
    expect(await prefs.read(), isNull);

    await prefs.clear();
    expect(await prefs.read(), isNull);
  });

  testWidgets('a remembered rider opens straight to Home', (tester) async {
    tester.view.physicalSize = const Size(400, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final first = launch();
    await tester.runAsync(() => signIn(first));
    final services = launch();
    services.demo!.networkAvailable = false;

    await tester.pumpWidget(QwikoApp(services: services));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Arjun 👋'), findsOneWidget);
    expect(find.text('Continue with phone'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });
}
