import 'geo_point.dart';
import 'media_ref.dart';

enum TicketStatus {
  open('Open'),
  awaitingYou('Waiting for your reply'),
  resolved('Resolved');

  const TicketStatus(this.label);

  final String label;
}

enum TicketSource { order, incident, help, chat }

enum MessageAuthor { rider, agent, system }

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.from,
    required this.text,
    required this.at,
    this.attachments = const [],
  });

  final String id;
  final MessageAuthor from;
  final String text;
  final DateTime at;
  final List<MediaRef> attachments;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.category,
    required this.source,
    required this.status,
    required this.createdAt,
    this.orderId,
    this.incidentId,
    this.messages = const [],
    this.agentTyping = false,
  });

  final String id;
  final String category;
  final TicketSource source;
  final TicketStatus status;
  final DateTime createdAt;
  final String? orderId;
  final String? incidentId;
  final List<SupportMessage> messages;

  /// An agent reply is on its way.
  final bool agentTyping;

  bool get isChat => source == TicketSource.chat;

  DateTime get updatedAt => messages.isEmpty ? createdAt : messages.last.at;

  SupportTicket copyWith({
    TicketStatus? status,
    List<SupportMessage>? messages,
    bool? agentTyping,
  }) => SupportTicket(
    id: id,
    category: category,
    source: source,
    status: status ?? this.status,
    createdAt: createdAt,
    orderId: orderId,
    incidentId: incidentId,
    messages: messages ?? this.messages,
    agentTyping: agentTyping ?? this.agentTyping,
  );

  @override
  bool operator ==(Object other) =>
      other is SupportTicket &&
      other.id == id &&
      other.status == status &&
      other.agentTyping == agentTyping &&
      other.messages.length == messages.length;

  @override
  int get hashCode => Object.hash(id, status, agentTyping, messages.length);
}

enum FaqCategory {
  orders('Orders'),
  payments('Payments'),
  account('Account'),
  safety('Safety'),
  app('App');

  const FaqCategory(this.label);

  final String label;
}

class FaqArticle {
  const FaqArticle({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    this.keywords = const [],
  });

  final String id;
  final FaqCategory category;
  final String question;
  final String answer;
  final List<String> keywords;
}

enum SafetyIncidentType {
  sos('SOS'),
  accident('Accident'),
  harassment('Harassment'),
  vehicleBreakdown('Vehicle breakdown'),
  unsafeLocation('Unsafe location'),
  other('Something else');

  const SafetyIncidentType(this.label);

  final String label;

  /// Types a rider can report from the incident form.
  static const reportable = [
    accident,
    harassment,
    vehicleBreakdown,
    unsafeLocation,
    other,
  ];
}

enum IncidentStatus {
  open('Open'),
  resolved('Closed');

  const IncidentStatus(this.label);

  final String label;
}

class SafetyIncident {
  const SafetyIncident({
    required this.id,
    required this.type,
    required this.at,
    required this.description,
    this.location,
    this.status = IncidentStatus.open,
    this.photo,
    this.ticketId,
    this.resolvedAt,
  });

  final String id;
  final SafetyIncidentType type;
  final DateTime at;
  final GeoPoint? location;
  final String description;
  final IncidentStatus status;
  final MediaRef? photo;
  final String? ticketId;
  final DateTime? resolvedAt;

  bool get isOpen => status == IncidentStatus.open;

  SafetyIncident resolve(DateTime at) => SafetyIncident(
    id: id,
    type: type,
    at: this.at,
    description: description,
    location: location,
    status: IncidentStatus.resolved,
    photo: photo,
    ticketId: ticketId,
    resolvedAt: at,
  );

  @override
  bool operator ==(Object other) =>
      other is SafetyIncident && other.id == id && other.status == status;

  @override
  int get hashCode => Object.hash(id, status);
}

class InsurancePolicy {
  const InsurancePolicy({
    required this.insurer,
    required this.policyNumber,
    required this.accidentCoverPaise,
    required this.hospitalCoverPaise,
    required this.validUntil,
    required this.claimSteps,
  });

  final String insurer;
  final String policyNumber;
  final int accidentCoverPaise;
  final int hospitalCoverPaise;
  final DateTime validUntil;
  final List<String> claimSteps;
}
