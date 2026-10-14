import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_routes.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/auth.dart';
import 'package:qwiko_delivery_agent/models/media_ref.dart';
import 'package:qwiko_delivery_agent/models/partner.dart';

void main() {
  late FakeClock clock;
  late AppServices services;

  setUp(() {
    clock = FakeClock(DateTime(2026, 10, 13, 14));
    services = AppServices.demo(clock: clock, latency: Duration.zero);
  });

  tearDown(() => services.dispose());

  Future<OtpFailure> wrongCode() async {
    try {
      await services.session.verifySignInOtp('000000');
    } on OtpFailure catch (failure) {
      return failure;
    }
    fail('Expected an OtpFailure');
  }

  group('sign-in OTP', () {
    test('rejects an invalid mobile number', () {
      expect(
        services.session.requestOtp('12345', OtpPurpose.signIn),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('123456 signs in to the current demo account', () async {
      await services.session.requestOtp('9123456780', OtpPurpose.signIn);
      final partner = await services.session.verifySignInOtp('123456');

      expect(services.session.isSignedIn, isTrue);
      expect(partner.verification, VerificationStatus.verified);
      expect(services.session.otpChallenge, isNull);
    });

    test(
      'three wrong codes lock entry for 30 s, then attempts reset',
      () async {
        await services.session.requestOtp('9123456780', OtpPurpose.signIn);

        expect((await wrongCode()).message, 'Incorrect OTP. 2 attempts left.');
        expect((await wrongCode()).message, 'Incorrect OTP. 1 attempt left.');
        final locked = await wrongCode();
        expect(locked.challenge.attemptsLeft, 0);
        expect(locked.challenge.isLockedAt(clock.now()), isTrue);
        expect(
          services.session.otpChallenge?.lockRemaining(clock.now()),
          const Duration(seconds: 30),
        );

        // Even the right code is refused while locked.
        expect(
          services.session.verifySignInOtp('123456'),
          throwsA(isA<OtpFailure>()),
        );
        await Future<void>.delayed(Duration.zero);

        clock.advance(const Duration(seconds: 30));
        expect(
          (await wrongCode()).message,
          'Incorrect OTP. 2 attempts left.',
          reason: 'a fresh set of attempts after the lockout',
        );
        await services.session.verifySignInOtp('123456');
        expect(services.session.isSignedIn, isTrue);
      },
    );

    test('resend is allowed only after 30 s and resets attempts', () async {
      await services.session.requestOtp('9123456780', OtpPurpose.signIn);
      await wrongCode();

      expect(services.session.resendOtp(), throwsA(isA<NotAllowedFailure>()));
      await Future<void>.delayed(Duration.zero);

      clock.advance(const Duration(seconds: 30));
      final challenge = await services.session.resendOtp();
      expect(challenge.attemptsLeft, OtpChallenge.maxAttempts);
      expect(challenge.resendIn(clock.now()), const Duration(seconds: 30));
    });

    test('resend is refused during a lockout', () async {
      await services.session.requestOtp('9123456780', OtpPurpose.signIn);
      for (var i = 0; i < 3; i++) {
        await wrongCode();
      }
      clock.advance(const Duration(seconds: 29));
      expect(services.session.resendOtp(), throwsA(isA<NotAllowedFailure>()));
    });

    test('email sign-in validates its fields', () {
      expect(
        services.session.signInWithEmail(email: 'nope', password: 'short'),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('password reset', () {
    test('OTP gives a single-use reset token', () async {
      await services.session.requestOtp('9123456780', OtpPurpose.resetPassword);
      final token = await services.session.verifyResetOtp('123456');

      await services.session.resetPassword(
        resetToken: token,
        newPassword: 'newpassword1',
      );
      expect(
        services.session.resetPassword(
          resetToken: token,
          newPassword: 'newpassword1',
        ),
        throwsA(isA<NotAllowedFailure>()),
      );
      expect(services.session.isSignedIn, isFalse);
    });

    test('sign-in and reset lockouts are independent', () async {
      await services.session.requestOtp('9123456780', OtpPurpose.signIn);
      for (var i = 0; i < 3; i++) {
        await wrongCode();
      }
      await services.session.requestOtp('9123456780', OtpPurpose.resetPassword);
      expect(await services.session.verifyResetOtp('123456'), isNotEmpty);
    });
  });

  group('account-state gate', () {
    Future<PartnerProfile> signInAs(DemoAccount account) async {
      services.demo!.useAccount(account);
      await services.session.requestOtp('9123456780', OtpPurpose.signIn);
      return services.session.verifySignInOtp('123456');
    }

    test('each demo account routes to its screen', () async {
      final expected = {
        DemoAccount.verified: AppRoutes.home,
        DemoAccount.newSignup: AppRoutes.kyc,
        DemoAccount.pending: AppRoutes.verificationPending,
        DemoAccount.rejectedDocument: AppRoutes.documentsResubmit,
        DemoAccount.suspended: AppRoutes.accountSuspended,
      };
      for (final MapEntry(key: account, value: route) in expected.entries) {
        final partner = await signInAs(account);
        expect(AppRoutes.forPartner(partner), route, reason: account.label);
        await services.session.signOut();
      }
    });

    test('blocked new accounts start without history', () async {
      await signInAs(DemoAccount.pending);
      await services.history.load();
      expect(services.history.items, isEmpty);
    });

    test('suspended accounts keep their history and reason', () async {
      final partner = await signInAs(DemoAccount.suspended);
      await services.history.load();
      expect(services.history.items, isNotEmpty);
      expect(partner.suspensionReason, isNotNull);
    });

    test('checking status does not approve on its own', () async {
      await signInAs(DemoAccount.pending);
      final profile = await services.profile.refreshVerification();
      expect(profile.verification, VerificationStatus.pending);
    });

    test('simulated approval verifies the account', () async {
      await signInAs(DemoAccount.pending);
      services.demo!.approveVerification();
      final partner = await services.session.refreshPartner();

      expect(partner.verification, VerificationStatus.verified);
      expect(
        partner.documents.map((d) => d.status),
        everyElement(DocumentStatus.verified),
      );
    });

    test(
      'simulated rejection needs a new upload before resubmitting',
      () async {
        await signInAs(DemoAccount.pending);
        services.demo!.rejectVerification();
        final partner = await services.session.refreshPartner();
        expect(AppRoutes.forPartner(partner), AppRoutes.documentsResubmit);
        expect(partner.rejectedDocuments.single.type, DocumentType.aadhaar);

        expect(
          services.profile.submitForVerification(),
          throwsA(isA<ValidationFailure>()),
        );
        await Future<void>.delayed(Duration.zero);

        await services.profile.saveDocuments({
          DocumentType.aadhaar: MediaRef.sample('new-aadhaar'),
        });
        final resubmitted = await services.profile.submitForVerification();
        expect(resubmitted.verification, VerificationStatus.pending);
      },
    );

    test('simulated reinstatement lifts a suspension', () async {
      await signInAs(DemoAccount.suspended);
      services.demo!.reinstateAccount();
      final partner = await services.session.refreshPartner();

      expect(AppRoutes.forPartner(partner), AppRoutes.home);
      expect(partner.suspensionReason, isNull);
    });

    test('reset keeps the chosen demo account', () async {
      services.demo!.useAccount(DemoAccount.suspended);
      services.demo!.resetData();
      expect(services.demo!.account, DemoAccount.suspended);
      final partner = await signInAs(DemoAccount.suspended);
      expect(partner.verification, VerificationStatus.suspended);
    });
  });

  test('support tickets can be created from a prefilled request', () async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.support.load();
    final before = services.support.tickets.length;

    final ticket = await services.support.createTicket(
      category: 'Account suspended',
      message: 'Please review my account.',
    );
    await Future<void>.delayed(Duration.zero);

    expect(services.support.tickets.length, before + 1);
    expect(services.support.tickets.first.id, ticket.id);
    expect(
      services.support.createTicket(category: 'Other', message: 'short'),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
