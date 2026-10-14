import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/widgets/otp_input.dart';

void main() {
  late FakeClock clock;
  late AppServices services;

  setUp(() {
    clock = FakeClock(DateTime(2026, 10, 13, 14));
    services = AppServices.demo(clock: clock, latency: Duration.zero);
  });

  tearDown(() => services.dispose());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Launches the app and goes past splash and the first-launch intro.
  Future<void> openLogin(WidgetTester tester) async {
    await tester.pumpWidget(QwikoApp(services: services));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Get started'));
    expect(find.text('Welcome back!'), findsOneWidget);
  }

  Finder otpField() => find.descendant(
    of: find.byType(OtpInput),
    matching: find.byType(TextField),
  );

  Future<void> requestPhoneOtp(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, '9123456780');
    await tap(tester, find.text('Continue with phone'));
    expect(find.text('Verify OTP'), findsOneWidget);
  }

  Future<void> signInWithPhone(WidgetTester tester) async {
    await requestPhoneOtp(tester);
    await tester.enterText(otpField(), '123456');
    await tester.pumpAndSettle();
  }

  testWidgets('First launch shows the demo intro once, then login', (
    tester,
  ) async {
    await tester.pumpWidget(QwikoApp(services: services));
    expect(find.text('Delivery Partner'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to the Qwiko partner demo'), findsOneWidget);

    await tap(tester, find.text('Get started'));
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(services.settings.settings.introSeen, isTrue);
    expect(
      find.text('Use any valid 10-digit mobile number and OTP 123456.'),
      findsOneWidget,
    );
  });

  testWidgets('Phone sign-in reaches Home in two steps', (tester) async {
    await openLogin(tester);
    await signInWithPhone(tester);

    expect(find.text('Hello, Arjun 👋'), findsOneWidget);
    expect(find.text("Today's summary"), findsOneWidget);
    expect(find.text('You are Offline'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('My Orders'), findsOneWidget);
    expect(find.textContaining('#QW'), findsWidgets);
  });

  testWidgets('Email sign-in validates and then opens Home', (tester) async {
    await openLogin(tester);
    await tap(tester, find.text('Sign in with email'));
    await tap(tester, find.text('Sign in'));
    expect(find.text('Please enter your email address'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'arjun@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    await tap(tester, find.text('Sign in'));
    expect(find.text('Hello, Arjun 👋'), findsOneWidget);
  });

  testWidgets('Phone field validates when it loses focus', (tester) async {
    await openLogin(tester);
    await tap(tester, find.text('Sign in with email'));
    await tester.enterText(find.byType(TextFormField).first, '12345');
    await tester.pump();
    expect(find.text('Enter a valid 10-digit mobile number'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(1), 'a');
    await tester.pump();
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
  });

  testWidgets('Wrong OTPs count down attempts, then lock with a countdown', (
    tester,
  ) async {
    await openLogin(tester);
    await requestPhoneOtp(tester);
    expect(find.text('Resend OTP in 0:30'), findsOneWidget);

    await tester.enterText(otpField(), '000000');
    await tester.pumpAndSettle();
    expect(find.text('Incorrect OTP. 2 attempts left.'), findsOneWidget);
    await tester.enterText(otpField(), '111111');
    await tester.pumpAndSettle();
    expect(find.text('Incorrect OTP. 1 attempt left.'), findsOneWidget);
    await tester.enterText(otpField(), '222222');
    await tester.pumpAndSettle();
    expect(find.textContaining('locked for 30 s'), findsOneWidget);
    expect(find.text('Try again in 0:30'), findsOneWidget);

    clock.advance(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Try again in 0:30'), findsNothing);
    expect(find.textContaining('locked for 30 s'), findsNothing);
    expect(find.text('Resend OTP'), findsOneWidget);

    await tester.enterText(otpField(), '123456');
    await tester.pumpAndSettle();
    expect(find.text('Hello, Arjun 👋'), findsOneWidget);
  });

  testWidgets('Forgot password resets with the demo OTP', (tester) async {
    await openLogin(tester);
    await tap(tester, find.text('Sign in with email'));
    await tap(tester, find.text('Forgot password?'));
    await tester.enterText(find.byType(TextFormField).first, '9123456780');
    await tap(tester, find.text('Send OTP'));
    await tester.enterText(otpField(), '123456');
    await tester.pumpAndSettle();

    expect(find.text('Create New Password'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'newpass123');
    await tester.enterText(find.byType(TextFormField).at(1), 'newpass123');
    await tap(tester, find.text('Reset password'));
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Password changed. Please sign in.'), findsOneWidget);
  });

  const landing = {
    DemoAccount.verified: 'Hello, Arjun 👋',
    DemoAccount.newSignup: 'Hi Arjun 👋',
    DemoAccount.pending: 'Profile under review',
    DemoAccount.rejectedDocument: 'Verification needs attention',
    DemoAccount.suspended: 'Account suspended',
  };
  for (final MapEntry(key: account, value: text) in landing.entries) {
    testWidgets('${account.label} account lands on its screen', (tester) async {
      services.demo!.useAccount(account);
      await openLogin(tester);
      expect(find.text('Demo account: ${account.label}'), findsOneWidget);
      await signInWithPhone(tester);

      expect(find.text(text), findsOneWidget);
      final blocked = {
        DemoAccount.pending,
        DemoAccount.rejectedDocument,
        DemoAccount.suspended,
      }.contains(account);
      if (blocked) {
        expect(find.byType(NavigationBar), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Log out'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Log out'), findsOneWidget);
        expect(find.text('Demo controls'), findsOneWidget);
        expect(find.text('Help'), findsOneWidget);
      }
    });
  }

  testWidgets('Simulated approval moves a pending account to Home', (
    tester,
  ) async {
    services.demo!.useAccount(DemoAccount.pending);
    await openLogin(tester);
    await signInWithPhone(tester);

    await tap(tester, find.text('Check status'));
    expect(
      find.text('Still under review. Please check later.'),
      findsOneWidget,
    );

    await tap(tester, find.text('Simulate approval'));
    expect(find.text('Hello, Arjun 👋'), findsOneWidget);
  });

  testWidgets('Simulated rejection highlights the document to re-upload', (
    tester,
  ) async {
    services.demo!.useAccount(DemoAccount.pending);
    await openLogin(tester);
    await signInWithPhone(tester);

    await tap(tester, find.text('Simulate rejection'));
    expect(find.text('Verification needs attention'), findsOneWidget);
    expect(find.text('Re-upload'), findsOneWidget);

    await tap(tester, find.text('Resubmit for verification'));
    expect(find.text('Upload a new Aadhaar Card first'), findsOneWidget);
  });

  testWidgets('Suspended account: contact support and reinstatement', (
    tester,
  ) async {
    services.demo!.useAccount(DemoAccount.suspended);
    await openLogin(tester);
    await signInWithPhone(tester);
    expect(find.textContaining('repeated customer complaints'), findsOneWidget);

    await tap(tester, find.text('Contact support'));
    expect(find.text('Contact support: Account suspended'), findsOneWidget);
    await tap(tester, find.text('Send to support'));
    expect(find.textContaining('sent to support'), findsOneWidget);
    await tester.runAsync(services.support.load);
    expect(services.support.tickets.first.category, 'Account suspended');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, find.text('Simulate reinstatement'));
    expect(find.text('Hello, Arjun 👋'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('Demo controls switch the account of a signed-in partner', (
    tester,
  ) async {
    await openLogin(tester);
    await signInWithPhone(tester);

    await tester.longPress(find.text('DEMO').first);
    await tester.pumpAndSettle();
    expect(find.text('Account state'), findsOneWidget);

    await tap(tester, find.text('Suspended'));
    await tap(tester, find.text('Switch account'));
    expect(find.text('Account suspended'), findsOneWidget);
    expect(find.text('Demo account: Suspended'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Log out'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(tester, find.text('Log out'));
    await tap(tester, find.text('Log out').last);
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(services.session.isSignedIn, isFalse);
  });

  group('Fits 320 dp at text scale 2.0', () {
    void useSmallScreen(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(320, 640) * 3
        ..devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    Future<void> scrollThrough(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.fling(
          find.byType(Scrollable).first,
          const Offset(0, -500),
          2000,
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('intro, login, OTP and main tabs', (tester) async {
      useSmallScreen(tester);
      await tester.pumpWidget(QwikoApp(services: services));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await scrollThrough(tester);
      await tap(tester, find.text('Get started'));
      await tap(tester, find.text('Sign in with email'));
      await scrollThrough(tester);
      await requestPhoneOtp(tester);
      await tester.enterText(otpField(), '000000');
      await tester.pumpAndSettle();
      await scrollThrough(tester);
      await tester.enterText(otpField(), '123456');
      await tester.pumpAndSettle();
      expect(find.text('Hello, Arjun 👋'), findsOneWidget);

      await scrollThrough(tester);
      for (final icon in [
        Icons.receipt_long_outlined,
        Icons.account_balance_wallet_outlined,
        Icons.person_outline_rounded,
      ]) {
        await tester.tap(find.byIcon(icon));
        await tester.pumpAndSettle();
        await scrollThrough(tester);
      }
      expect(tester.takeException(), isNull);
    });

    for (final account in [
      DemoAccount.pending,
      DemoAccount.rejectedDocument,
      DemoAccount.suspended,
    ]) {
      testWidgets('${account.label} screen', (tester) async {
        useSmallScreen(tester);
        services.demo!.useAccount(account);
        await openLogin(tester);
        await signInWithPhone(tester);
        expect(find.text(landing[account]!), findsOneWidget);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
