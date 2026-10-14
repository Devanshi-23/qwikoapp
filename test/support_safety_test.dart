import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_routes.dart';
import 'package:qwiko_delivery_agent/app/app_scope.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/app/app_theme.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/core/failures.dart';
import 'package:qwiko_delivery_agent/models/support.dart';
import 'package:qwiko_delivery_agent/screens/safety/safety_screen.dart';
import 'package:qwiko_delivery_agent/screens/support/help_support_screen.dart';
import 'package:qwiko_delivery_agent/widgets/hold_to_confirm.dart';

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

  group('Support', () {
    test('an agent answers a ticket reply and the rider is notified', () async {
      final support = services.support;
      await support.load();
      final ticket = await support.createTicket(
        category: 'Payout delay',
        message: 'My payout from Monday has not arrived yet.',
      );
      expect(ticket.agentTyping, isTrue);

      clock.advance(const Duration(seconds: 9));
      await support.refresh();
      final answered = support.ticketById(ticket.id)!;
      expect(answered.agentTyping, isFalse);
      expect(answered.status, TicketStatus.awaitingYou);
      expect(answered.messages.last.from, MessageAuthor.agent);
      expect(answered.messages.last.text, contains('Payouts'));
      expect(support.tickets.first.id, ticket.id);

      await services.notifications.load();
      final latest = services.notifications.items.first;
      expect(latest.title, 'Support replied · ${ticket.id}');
      expect(latest.deepLink?.id, ticket.id);

      await support.reply(ticket.id, 'Thanks, I will check again tonight.');
      expect(support.ticketById(ticket.id)!.status, TicketStatus.open);
      await expectLater(
        support.reply(ticket.id, '   '),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'live chat replies quickly; resolving stops pending replies',
      () async {
        final support = services.support;
        await support.load();
        final chat = await support.startChat('App issue');
        expect(chat.isChat, isTrue);

        clock.advance(const Duration(seconds: 4));
        await support.refresh();
        expect(
          support.ticketById(chat.id)!.messages.last.text,
          contains('Priya'),
        );

        await support.reply(chat.id, 'The app keeps getting stuck on the map.');
        await support.resolve(chat.id);
        clock.advance(const Duration(seconds: 10));
        await support.refresh();
        final closed = support.ticketById(chat.id)!;
        expect(closed.status, TicketStatus.resolved);
        expect(closed.messages.last.from, MessageAuthor.system);
      },
    );

    test('FAQ search matches words, keywords and categories', () async {
      final support = services.support;
      await support.load();
      expect(support.faqs.length, greaterThanOrEqualTo(25));
      expect(
        support.searchFaqs('insurance').map((f) => f.id),
        contains('faq-insurance'),
      );
      expect(
        support
            .searchFaqs('', category: FaqCategory.safety)
            .every((f) => f.category == FaqCategory.safety),
        isTrue,
      );
      expect(support.searchFaqs('zzz unknown'), isEmpty);
    });
  });

  group('Safety', () {
    test('an incident report is validated and opens a linked ticket', () async {
      final safety = services.safety;
      await safety.load();
      expect(safety.insurance, isNotNull);

      await expectLater(
        safety.reportIncident(
          type: SafetyIncidentType.accident,
          at: clock.now(),
          description: 'Fell off',
        ),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        safety.reportIncident(
          type: SafetyIncidentType.accident,
          at: clock.now().add(const Duration(hours: 1)),
          description: 'A car hit my scooter at the signal near the market.',
        ),
        throwsA(isA<ValidationFailure>()),
      );

      final incident = await safety.reportIncident(
        type: SafetyIncidentType.harassment,
        at: clock.now().subtract(const Duration(minutes: 20)),
        description: 'The store guard shouted at me and refused entry.',
      );
      expect(incident.ticketId, isNotNull);
      expect(safety.incidents.first.id, incident.id);

      await services.support.load();
      final ticket = services.support.ticketById(incident.ticketId!)!;
      expect(ticket.source, TicketSource.incident);
      expect(ticket.incidentId, incident.id);
    });
  });

  test('"Call 112" is the only external launch in the app', () {
    final launches = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('launchUrl('))
          file.path.replaceAll(r'\', '/'),
    ];
    expect(launches, ['lib/screens/safety/call_112.dart']);
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

  Future<void> scrollTo(WidgetTester tester, Finder finder, double delta) =>
      tester.scrollUntilVisible(
        finder,
        delta,
        scrollable: find.byType(Scrollable).first,
      );

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  Future<void> hold(WidgetTester tester, Duration duration) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t <= duration + step * 3; t += step) {
      await tester.pump(step);
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('SOS needs a hold, can be cancelled, then alerts', (
    tester,
  ) async {
    await pumpScreen(tester, const SafetyScreen());
    final before = services.safety.incidents.length;

    await tester.tap(find.byType(HoldToConfirmButton));
    await tester.pumpAndSettle();
    await hold(tester, const Duration(seconds: 1));
    expect(find.text('Sending SOS in'), findsNothing);

    await hold(tester, const Duration(seconds: 3));
    expect(find.text('Sending SOS in'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Cancel SOS'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(services.safety.incidents, hasLength(before));
    expect(services.safety.activeSos, isNull);

    await hold(tester, const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Alert sent'), findsOneWidget);
    expect(find.text('Sunita Mehta got your live location.'), findsOneWidget);
    expect(services.safety.activeSos, isNotNull);
    await services.notifications.load();
    expect(services.notifications.items.first.title, 'SOS alert sent');

    await scrollTo(tester, find.text("I'm safe now"), 200);
    await tester.tap(find.text("I'm safe now"));
    await tester.pumpAndSettle();
    expect(services.safety.activeSos, isNull);
    expect(find.text("Glad you're safe. Alert closed."), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Help search, article feedback and live chat', (tester) async {
    await pumpScreen(tester, const HelpSupportScreen());

    await scrollTo(tester, find.byType(TextField), 200);
    await tester.enterText(find.byType(TextField), 'insurance');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Am I insured while delivering?'), 200);
    await tester.tap(find.text('Am I insured while delivering?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, contact support'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Contact support: Safety'), -200);
    expect(find.text('Contact support: Safety'), findsOneWidget);

    await scrollTo(tester, find.text('Chat'), -200);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payout delay'));
    await tester.pumpAndSettle();
    expect(find.text('Chat with support'), findsOneWidget);
    expect(find.text('Support is typing…'), findsOneWidget);

    clock.advance(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    await tester.runAsync(services.support.refresh);
    await tester.pumpAndSettle();
    expect(find.text('Support is typing…'), findsNothing);
    expect(find.textContaining('Priya'), findsOneWidget);
    await finish(tester);
  });
}
