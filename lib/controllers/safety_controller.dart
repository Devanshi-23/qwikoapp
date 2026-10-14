import '../core/domain_events.dart';
import '../data/repositories/support_repository.dart';
import '../models/geo_point.dart';
import '../models/media_ref.dart';
import '../models/support.dart';
import 'loadable_controller.dart';

/// SOS, incident reports and insurance.
class SafetyController extends LoadableController {
  SafetyController({
    required this._repository,
    required this._position,
    super.events,
  });

  final SafetyRepository _repository;
  final GeoPoint? Function() _position;

  List<SafetyIncident> _incidents = const [];
  InsurancePolicy? _insurance;
  bool _sending = false;

  /// Newest first.
  List<SafetyIncident> get incidents => _incidents;

  InsurancePolicy? get insurance => _insurance;

  bool get isSending => _sending;

  /// The SOS alert still waiting for "I'm safe now".
  SafetyIncident? get activeSos => _incidents
      .where((i) => i.type == SafetyIncidentType.sos && i.isOpen)
      .firstOrNull;

  @override
  Future<void> fetch() async {
    final results = await Future.wait<Object>([
      _repository.incidents(),
      _repository.insurance(),
    ]);
    _incidents = results[0] as List<SafetyIncident>;
    _insurance = results[1] as InsurancePolicy;
  }

  @override
  void clearData() {
    _incidents = const [];
    _insurance = null;
  }

  @override
  bool shouldRefresh(DomainEvent event) => event is SafetyChanged;

  Future<SafetyIncident> _run(Future<SafetyIncident> Function() action) =>
      runBusy(
        (busy) {
          _sending = busy;
          notify();
        },
        () async {
          final incident = await action();
          _incidents = [
            incident,
            for (final i in _incidents)
              if (i.id != incident.id) i,
          ]..sort((a, b) => b.at.compareTo(a.at));
          return incident;
        },
      );

  Future<SafetyIncident> raiseSos() =>
      _run(() => _repository.raiseSos(_position()));

  Future<SafetyIncident> markSafe(String incidentId) =>
      _run(() => _repository.markSafe(incidentId));

  Future<SafetyIncident> reportIncident({
    required SafetyIncidentType type,
    required DateTime at,
    required String description,
    MediaRef? photo,
  }) => _run(
    () => _repository.reportIncident(
      type: type,
      at: at,
      description: description,
      photo: photo,
      location: _position(),
    ),
  );
}
