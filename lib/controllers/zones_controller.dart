import '../core/domain_events.dart';
import '../data/repositories/zone_repository.dart';
import '../models/geo_point.dart';
import '../models/zone.dart';
import 'loadable_controller.dart';

/// Zones and their current demand, for the demand nudge and heat map.
class ZonesController extends LoadableController {
  ZonesController({required this._repository, super.events});

  final ZoneRepository _repository;

  List<DeliveryZone> _zones = const [];

  List<DeliveryZone> get zones => _zones;

  DeliveryZone? byId(String? id) {
    for (final zone in _zones) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  /// The busiest zone other than [currentZoneId], nearest to [from] among
  /// equally busy zones. Null when no other zone is busy.
  DeliveryZone? hottestNearby(String? currentZoneId, GeoPoint from) {
    final busy = _zones
        .where((z) => z.id != currentZoneId && z.demand.isBusy)
        .toList();
    if (busy.isEmpty) return null;
    busy.sort((a, b) {
      final byMultiplier = b.surgeMultiplier.compareTo(a.surgeMultiplier);
      if (byMultiplier != 0) return byMultiplier;
      return from
          .distanceMetersTo(a.center)
          .compareTo(from.distanceMetersTo(b.center));
    });
    return busy.first;
  }

  @override
  Future<void> fetch() async => _zones = await _repository.zones();

  @override
  void clearData() => _zones = const [];

  /// Demand follows the clock, so any rider activity is a cue to re-check.
  @override
  bool shouldRefresh(DomainEvent event) =>
      event is DemandChanged || event is ActivityChanged;
}
