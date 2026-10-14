import '../../models/zone.dart';

abstract interface class ZoneRepository {
  /// Every zone with its current demand.
  Future<List<DeliveryZone>> zones();
}
