import '../core/domain_events.dart';
import '../data/repositories/support_repository.dart';
import '../models/media_ref.dart';
import '../models/support.dart';
import 'loadable_controller.dart';

class SupportController extends LoadableController {
  SupportController({required this._repository, super.events});

  final SupportRepository _repository;

  List<FaqArticle> _faqs = const [];
  List<SupportTicket> _tickets = const [];
  bool _sending = false;

  List<FaqArticle> get faqs => _faqs;

  /// Most recently updated first.
  List<SupportTicket> get tickets => _tickets;

  bool get isSending => _sending;

  SupportTicket? ticketById(String id) =>
      _tickets.where((t) => t.id == id).firstOrNull;

  /// Matches the question, answer or keywords; an empty query matches all.
  List<FaqArticle> searchFaqs(String query, {FaqCategory? category}) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    return [
      for (final faq in _faqs)
        if (category == null || faq.category == category)
          if (words.every(
            (w) =>
                faq.question.toLowerCase().contains(w) ||
                faq.answer.toLowerCase().contains(w) ||
                faq.keywords.any((k) => k.contains(w)),
          ))
            faq,
    ];
  }

  @override
  Future<void> fetch() async {
    final results = await Future.wait<Object>([
      _repository.faqs(),
      _repository.tickets(),
    ]);
    _faqs = results[0] as List<FaqArticle>;
    _tickets = results[1] as List<SupportTicket>;
  }

  @override
  void clearData() {
    _faqs = const [];
    _tickets = const [];
  }

  @override
  bool shouldRefresh(DomainEvent event) => event is SupportChanged;

  Future<SupportTicket> _send(Future<SupportTicket> Function() action) =>
      runBusy(
        (busy) {
          _sending = busy;
          notify();
        },
        () async {
          final ticket = await action();
          _tickets = [
            ticket,
            for (final t in _tickets)
              if (t.id != ticket.id) t,
          ];
          return ticket;
        },
      );

  Future<SupportTicket> createTicket({
    required String category,
    required String message,
    TicketSource source = TicketSource.help,
    String? orderId,
    List<MediaRef> attachments = const [],
  }) => _send(
    () => _repository.createTicket(
      category: category,
      message: message,
      source: source,
      orderId: orderId,
      attachments: attachments,
    ),
  );

  Future<SupportTicket> reply(
    String ticketId,
    String text, {
    List<MediaRef> attachments = const [],
  }) =>
      _send(() => _repository.reply(ticketId, text, attachments: attachments));

  Future<SupportTicket> resolve(String ticketId) =>
      _send(() => _repository.resolve(ticketId));

  Future<SupportTicket> startChat(String topic) =>
      _send(() => _repository.startChat(topic));
}
