import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_routes.dart';
import 'package:qwiko_delivery_agent/app/app_scope.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/app/app_theme.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/models/media_ref.dart';
import 'package:qwiko_delivery_agent/models/notification.dart';
import 'package:qwiko_delivery_agent/models/partner.dart';
import 'package:qwiko_delivery_agent/screens/notifications/notifications_screen.dart';
import 'package:qwiko_delivery_agent/screens/profile/emergency_contacts_screen.dart';
import 'package:qwiko_delivery_agent/screens/profile/personal_details_screen.dart';
import 'package:qwiko_delivery_agent/screens/settings/settings_screen.dart';

void main() {
  late AppServices services;
  late FakeClock clock;

  setUp(() async {
    services = AppServices.demo(
      clock: clock = FakeClock(DateTime(2026, 10, 13, 14)),
      latency: Duration.zero,
      firstOfferDelay: const Duration(minutes: 30),
      offerInterval: const Duration(minutes: 30),
    );
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
  });

  tearDown(() => services.dispose());

  Future<List<AppNotification>> inbox() async {
    await services.notifications.load();
    return services.notifications.items;
  }

  group('Reviews', () {
    test('a changed bank account is verified after the review', () async {
      final profile = services.profile;
      await profile.load();
      final bank = profile.profile!.bank!;
      await profile.updateBank(
        bank.copyWith(verification: BankVerification.verifying),
        upiId: '',
      );
      expect(profile.profile!.bank!.verification, BankVerification.verifying);

      clock.advance(const Duration(seconds: 11));
      await profile.refresh();
      expect(profile.profile!.bank!.verification, BankVerification.verified);
      expect((await inbox()).first.title, 'Bank verified');
    });

    test('a re-upload can be rejected with a reason', () async {
      services.demo!.rejectNextDocument = true;
      final profile = services.profile;
      await profile.saveDocuments({
        DocumentType.insurance: const MediaRef.sample('doc-insurance'),
      });
      expect(
        profile.profile!.documentFor(DocumentType.insurance).status,
        DocumentStatus.pending,
      );

      clock.advance(const Duration(seconds: 11));
      await profile.refresh();
      final doc = profile.profile!.documentFor(DocumentType.insurance);
      expect(doc.status, DocumentStatus.rejected);
      expect(doc.rejectionReason, isNotEmpty);
      expect(services.demo!.rejectNextDocument, isFalse);
      final latest = (await inbox()).first;
      expect(latest.title, contains('rejected'));
      expect(latest.deepLink?.id, DocumentType.insurance.name);
    });
  });

  group('Notification settings', () {
    test(
      'muted categories stay out of the inbox; safety cannot be muted',
      () async {
        final settings = services.settings;
        await settings.load();
        await settings.setCategoryEnabled(NotificationCategory.account, false);
        await settings.setCategoryEnabled(NotificationCategory.safety, false);
        expect(settings.settings.allows(NotificationCategory.safety), isTrue);

        final before = (await inbox()).length;
        final bank = services.profile.profile!.bank!;
        await services.profile.updateBank(
          bank.copyWith(verification: BankVerification.verifying),
          upiId: '',
        );
        clock.advance(const Duration(seconds: 11));
        await services.profile.refresh();
        expect(
          services.profile.profile!.bank!.verification,
          BankVerification.verified,
        );
        expect((await inbox()).length, before);
      },
    );

    test('inbox filter shows one category at a time', () async {
      final notifications = services.notifications;
      await notifications.load();
      notifications.setFilter(NotificationCategory.earnings);
      expect(notifications.visibleItems, isNotEmpty);
      expect(
        notifications.visibleItems.every(
          (n) => n.category == NotificationCategory.earnings,
        ),
        isTrue,
      );
      notifications.setFilter(null);
      expect(notifications.visibleItems, notifications.items);
    });
  });

  test('up to three emergency contacts', () async {
    const contact = EmergencyContact(
      name: 'A',
      relation: 'Friend',
      phone: '9000000001',
    );
    await services.profile.updateEmergencyContacts([contact, contact, contact]);
    expect(services.profile.profile!.emergencyContacts, hasLength(3));
    await expectLater(
      services.profile.updateEmergencyContacts([
        contact,
        contact,
        contact,
        contact,
      ]),
      throwsA(isA<ValidationFailure>()),
    );
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(400, 860) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildAppTheme(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  testWidgets('the profile photo can be removed; the KYC selfie stays', (
    tester,
  ) async {
    final profile = services.profile;
    await profile.updatePersonal(
      name: profile.profile!.name,
      email: profile.profile!.email,
      phone: profile.profile!.phone,
      address: profile.profile!.address,
      photo: const MediaRef.sample('selfie'),
    );
    await pumpScreen(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const PersonalDetailsScreen(),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(find.text('Remove photo'), findsNothing);
    expect(find.text('Add photo'), findsOneWidget);

    await tester.ensureVisible(find.text('Save Details'));
    await tester.tap(find.text('Save Details'));
    await tester.pumpAndSettle();
    expect(find.text('Personal details saved'), findsOneWidget);
    expect(profile.profile!.photo, isNull);
    expect(
      profile.profile!.documentFor(DocumentType.photo).media,
      const MediaRef.sample('selfie'),
    );
    await finish(tester);
  });

  testWidgets('tapping a payout notification opens Payouts', (tester) async {
    await pumpScreen(tester, const NotificationsScreen());
    await tester.tap(find.text('Money'));
    await tester.pumpAndSettle();
    final payout = services.notifications.visibleItems.firstWhere(
      (n) => n.deepLink != null,
    );
    await tester.tap(find.text(payout.title));
    await tester.pumpAndSettle();
    expect(find.text('Payouts'), findsWidgets);
    expect(
      services.notifications.items.firstWhere((n) => n.id == payout.id).isRead,
      isTrue,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    services.notifications.setFilter(NotificationCategory.safety);
    await tester.pumpAndSettle();
    if (services.notifications.visibleItems.isEmpty) {
      expect(find.text('No safety notifications'), findsOneWidget);
    }
    await finish(tester);
  });

  testWidgets('emergency contacts validate the number', (tester) async {
    await pumpScreen(tester, const EmergencyContactsScreen());
    expect(find.text('Sunita Mehta'), findsOneWidget);

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Ravi');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Relation'),
      'Brother',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number'),
      services.profile.profile!.phone,
    );
    await tester.tap(find.text('Save contact'));
    await tester.pumpAndSettle();
    expect(find.text('This is your own number'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number'),
      '9811122334',
    );
    await tester.tap(find.text('Save contact'));
    await tester.pumpAndSettle();
    expect(find.text('This number is already a contact'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number'),
      '9822233445',
    );
    await tester.tap(find.text('Save contact'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi added'), findsOneWidget);
    expect(services.profile.profile!.emergencyContacts, hasLength(2));
    await finish(tester);
  });

  testWidgets('settings lock safety alerts and unbuilt options', (
    tester,
  ) async {
    await pumpScreen(tester, const SettingsScreen());
    final safety = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Safety'),
    );
    expect(safety.onChanged, isNull);
    expect(safety.value, isTrue);

    await tester.scrollUntilVisible(find.text('Language'), 200);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(
      find.text('Hindi and regional languages are coming in a later update.'),
      findsOneWidget,
    );
    final hindi = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'हिन्दी (Hindi)'),
    );
    expect(hindi.enabled, isFalse);
    await finish(tester);
  });
}
