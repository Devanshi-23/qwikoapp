import 'geo_point.dart';

enum DemandLevel {
  low('Low demand'),
  normal('Normal demand'),
  high('High demand'),
  surge('Very high demand');

  const DemandLevel(this.label);

  final String label;

  bool get isBusy => this == high || this == surge;
}

class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.name,
    required this.center,
    this.demand = DemandLevel.normal,
    this.surgeMultiplier = 1.0,
  });

  final String id;
  final String name;
  final GeoPoint center;
  final DemandLevel demand;
  final double surgeMultiplier;

  DeliveryZone copyWith({DemandLevel? demand, double? surgeMultiplier}) =>
      DeliveryZone(
        id: id,
        name: name,
        center: center,
        demand: demand ?? this.demand,
        surgeMultiplier: surgeMultiplier ?? this.surgeMultiplier,
      );

  @override
  bool operator ==(Object other) =>
      other is DeliveryZone &&
      other.id == id &&
      other.demand == demand &&
      other.surgeMultiplier == surgeMultiplier;

  @override
  int get hashCode => Object.hash(id, demand, surgeMultiplier);

  @override
  String toString() => 'DeliveryZone($id, ${demand.name})';
}
