import 'dart:async';

import '../../core/domain_events.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../models/activity.dart';
import '../../models/app_link.dart';
import '../../models/geo_point.dart';
import '../../models/media_ref.dart';
import '../../models/notification.dart';
import '../../models/support.dart';
import '../repositories/demo_controls.dart';
import '../repositories/support_repository.dart';
import 'demo_backend.dart';
import 'demo_catalog.dart';

/// Tickets and live chat with a simulated agent. Agent replies are due on
/// the clock: a timer delivers them, and every read also settles them.
class DemoSupportRepository implements SupportRepository {
  DemoSupportRepository(this._backend);

  final DemoBackend _backend;

  static const ticketReplyAfter = Duration(seconds: 8);
  static const chatReplyAfter = Duration(seconds: 3);

  /// Ticket id → when the agent answers, and what they say.
  final Map<String, ({DateTime due, String text})> _pending = {};

  List<SupportTicket> get _tickets => _backend.db.tickets;

  SupportTicket _find(String id) {
    final ticket = _tickets.where((t) => t.id == id).firstOrNull;
    if (ticket == null) throw const NotFoundFailure('This request was closed.');
    return ticket;
  }

  void _put(SupportTicket ticket) {
    _tickets
      ..removeWhere((t) => t.id == ticket.id)
      ..insert(0, ticket);
    _backend.events.emit(const SupportChanged());
  }

  SupportMessage _message(
    MessageAuthor from,
    String text, {
    List<MediaRef> attachments = const [],
  }) => SupportMessage(
    id: _backend.ids.next('msg'),
    from: from,
    text: text,
    at: _backend.clock.now(),
    attachments: attachments,
  );

  void _scheduleReply(SupportTicket ticket, String text) {
    final delay = ticket.isChat ? chatReplyAfter : ticketReplyAfter;
    _pending[ticket.id] = (due: _backend.clock.now().add(delay), text: text);
    Timer(delay, () {
      if (!_backend.events.isClosed) _settle();
    });
  }

  void _settle() {
    final now = _backend.clock.now();
    for (final MapEntry(key: id, value: reply) in [..._pending.entries]) {
      if (now.isBefore(reply.due)) continue;
      _pending.remove(id);
      final ticket = _tickets.where((t) => t.id == id).firstOrNull;
      if (ticket == null || ticket.status == TicketStatus.resolved) continue;
      final answer = SupportMessage(
        id: _backend.ids.next('msg'),
        from: MessageAuthor.agent,
        text: reply.text,
        at: reply.due,
      );
      _put(
        ticket.copyWith(
          status: TicketStatus.awaitingYou,
          messages: [...ticket.messages, answer],
        ),
      );
      if (!ticket.isChat) {
        _backend.notify(
          NotificationCategory.system,
          'Support replied · ${ticket.id}',
          reply.text,
          link: AppLink(AppLinkRoute.ticket, ticket.id),
        );
      }
    }
  }

  static String agentAnswer(String topic, String text) {
    final words = '$topic $text'.toLowerCase();
    bool has(List<String> keys) => keys.any(words.contains);
    if (has(['payout', 'withdraw', 'bank', 'money'])) {
      return 'I can see your payouts. Instant payouts reach your bank within '
          'minutes; if one failed, the money is back in your balance and you '
          'can tap Retry on the Payouts screen.';
    }
    if (has(['app', 'crash', 'slow', 'bug', 'stuck'])) {
      return 'Sorry about that. Please close and reopen the app and check '
          'that location is on. If it happens again, send a screenshot here.';
    }
    if (has(['order', 'tip', 'pay', 'distance'])) {
      return "Thanks, I've checked the order. We'll review it and update you "
          'here within 24 hours.';
    }
    if (has(['sos', 'safety', 'accident', 'harass', 'unsafe'])) {
      return 'Our safety team has your report. Are you safe right now? Reply '
          'here and we will call you back.';
    }
    return "Thanks for the details. I'm looking into this and will update "
        'you here.';
  }

  @override
  Future<List<FaqArticle>> faqs() => _backend.engine.run(
    OperationType.loadSupport,
    () => List.unmodifiable(_backend.db.faqs),
  );

  @override
  Future<List<SupportTicket>> tickets() =>
      _backend.engine.run(OperationType.loadSupport, () {
        _settle();
        final sorted = [..._tickets]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return List.unmodifiable([
          for (final t in sorted)
            _pending.containsKey(t.id) ? t.copyWith(agentTyping: true) : t,
        ]);
      });

  @override
  Future<SupportTicket> createTicket({
    required String category,
    required String message,
    TicketSource source = TicketSource.help,
    String? orderId,
    String? incidentId,
    List<MediaRef> attachments = const [],
  }) => _backend.engine.run(OperationType.createTicket, () {
    final text = message.trim();
    if (text.length < 10) {
      throw const ValidationFailure(
        'Tell us a little more (at least 10 characters).',
        field: 'message',
      );
    }
    final ticket = SupportTicket(
      id: _backend.ids.next('TKT'),
      category: category,
      source: source,
      status: TicketStatus.open,
      createdAt: _backend.clock.now(),
      orderId: orderId,
      incidentId: incidentId,
      messages: [
        _message(MessageAuthor.rider, text, attachments: attachments),
        _message(
          MessageAuthor.system,
          "We've received your request. An agent will reply within 24 hours.",
        ),
      ],
    );
    _put(ticket);
    _scheduleReply(ticket, agentAnswer(category, text));
    return ticket.copyWith(agentTyping: true);
  });

  @override
  Future<SupportTicket> reply(
    String ticketId,
    String text, {
    List<MediaRef> attachments = const [],
  }) => _backend.engine.run(OperationType.sendSupportMessage, () {
    final error = Validators.chatMessage(text);
    if (error != null && attachments.isEmpty) {
      throw ValidationFailure(error, field: 'message');
    }
    final ticket = _find(ticketId);
    final updated = ticket.copyWith(
      status: TicketStatus.open,
      messages: [
        ...ticket.messages,
        _message(MessageAuthor.rider, text.trim(), attachments: attachments),
      ],
    );
    _put(updated);
    _scheduleReply(updated, agentAnswer(ticket.category, text));
    return updated.copyWith(agentTyping: true);
  });

  @override
  Future<SupportTicket> resolve(String ticketId) =>
      _backend.engine.run(OperationType.sendSupportMessage, () {
        final ticket = _find(ticketId);
        _pending.remove(ticketId);
        final updated = ticket.copyWith(
          status: TicketStatus.resolved,
          messages: [
            ...ticket.messages,
            _message(MessageAuthor.system, 'You marked this as resolved.'),
          ],
        );
        _put(updated);
        return updated;
      });

  @override
  Future<SupportTicket> startChat(String topic) =>
      _backend.engine.run(OperationType.createTicket, () {
        final ticket = SupportTicket(
          id: _backend.ids.next('CHT'),
          category: topic,
          source: TicketSource.chat,
          status: TicketStatus.open,
          createdAt: _backend.clock.now(),
          messages: [
            _message(
              MessageAuthor.system,
              "You're chatting with a simulated support agent.",
            ),
          ],
        );
        _put(ticket);
        _scheduleReply(
          ticket,
          'Hi ${_backend.db.partner.firstName}, this is Priya from Qwiko '
          'support. ${agentAnswer(topic, '')}',
        );
        return ticket.copyWith(agentTyping: true);
      });
}

class DemoSafetyRepository implements SafetyRepository {
  DemoSafetyRepository(this._backend, this._support);

  final DemoBackend _backend;
  final DemoSupportRepository _support;

  List<SafetyIncident> get _incidents => _backend.db.incidents;

  void _changed() => _backend.events.emit(const SafetyChanged());

  @override
  Future<List<SafetyIncident>> incidents() => _backend.engine.run(
    OperationType.loadSafety,
    () => List.unmodifiable(_incidents),
  );

  @override
  Future<InsurancePolicy> insurance() =>
      _backend.engine.run(OperationType.loadSafety, () => demoInsurance);

  @override
  Future<SafetyIncident> raiseSos(GeoPoint? location) => _backend.engine.run(
    OperationType.sos,
    () {
      final open = _incidents
          .where((i) => i.type == SafetyIncidentType.sos && i.isOpen)
          .firstOrNull;
      if (open != null) return open;
      final now = _backend.clock.now();
      final contacts = _backend.db.partner.emergencyContacts;
      final incident = SafetyIncident(
        id: _backend.ids.next('INC'),
        type: SafetyIncidentType.sos,
        at: now,
        location: location,
        description: contacts.isEmpty
            ? 'SOS raised. Safety team alerted.'
            : 'SOS raised. Safety team and ${contacts.length} emergency '
                  'contact${contacts.length == 1 ? '' : 's'} alerted.',
      );
      _incidents.insert(0, incident);
      _backend.recordActivity(ActivityType.sos, 'Raised at ${formatTime(now)}');
      _backend.notify(
        NotificationCategory.safety,
        'SOS alert sent',
        'Our safety team is calling you. Tap to open Safety.',
        link: const AppLink(AppLinkRoute.safety),
      );
      _changed();
      return incident;
    },
  );

  @override
  Future<SafetyIncident> markSafe(String incidentId) =>
      _backend.engine.run(OperationType.sos, () {
        final index = _incidents.indexWhere((i) => i.id == incidentId);
        if (index < 0) throw const NotFoundFailure('This alert was closed.');
        final resolved = _incidents[index].resolve(_backend.clock.now());
        _incidents[index] = resolved;
        _backend.recordActivity(ActivityType.sos, 'Marked safe');
        _changed();
        return resolved;
      });

  @override
  Future<SafetyIncident> reportIncident({
    required SafetyIncidentType type,
    required DateTime at,
    required String description,
    MediaRef? photo,
    GeoPoint? location,
  }) async {
    final error = Validators.incidentDescription(description);
    if (error != null) throw ValidationFailure(error, field: 'description');
    if (at.isAfter(_backend.clock.now())) {
      throw const ValidationFailure(
        "The time can't be in the future.",
        field: 'at',
      );
    }
    final id = _backend.ids.next('INC');
    final ticket = await _support.createTicket(
      category: 'Safety: ${type.label}',
      message: description,
      source: TicketSource.incident,
      incidentId: id,
      attachments: [?photo],
    );
    final incident = SafetyIncident(
      id: id,
      type: type,
      at: at,
      description: description.trim(),
      location: location,
      photo: photo,
      ticketId: ticket.id,
    );
    _incidents.insert(0, incident);
    _backend.notify(
      NotificationCategory.safety,
      '${type.label} reported',
      'Request ${ticket.id} is open. Our safety team will contact you.',
      link: AppLink(AppLinkRoute.ticket, ticket.id),
    );
    _changed();
    return incident;
  }
}
