import '../../models/geo_point.dart';
import '../../models/media_ref.dart';
import '../../models/support.dart';

abstract interface class SupportRepository {
  Future<List<FaqArticle>> faqs();

  /// Newest activity first.
  Future<List<SupportTicket>> tickets();

  Future<SupportTicket> createTicket({
    required String category,
    required String message,
    TicketSource source = TicketSource.help,
    String? orderId,
    String? incidentId,
    List<MediaRef> attachments = const [],
  });

  /// Adds the rider's message; an agent answers later.
  Future<SupportTicket> reply(
    String ticketId,
    String text, {
    List<MediaRef> attachments = const [],
  });

  Future<SupportTicket> resolve(String ticketId);

  /// Opens a live chat about [topic]; an agent joins shortly.
  Future<SupportTicket> startChat(String topic);
}

abstract interface class SafetyRepository {
  /// Newest first.
  Future<List<SafetyIncident>> incidents();

  Future<InsurancePolicy> insurance();

  /// Alerts support and emergency contacts. Works offline (queued).
  Future<SafetyIncident> raiseSos(GeoPoint? location);

  Future<SafetyIncident> markSafe(String incidentId);

  /// Records the incident and opens a linked support ticket.
  Future<SafetyIncident> reportIncident({
    required SafetyIncidentType type,
    required DateTime at,
    required String description,
    MediaRef? photo,
    GeoPoint? location,
  });
}
