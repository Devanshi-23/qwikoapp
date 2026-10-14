import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// A position on the map. Wraps latlong2 so models do not depend on a map SDK.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  factory GeoPoint.fromLatLng(LatLng point) =>
      GeoPoint(point.latitude, point.longitude);

  final double latitude;
  final double longitude;

  LatLng toLatLng() => LatLng(latitude, longitude);

  int distanceMetersTo(GeoPoint other) => const Distance()
      .as(LengthUnit.Meter, toLatLng(), other.toLatLng())
      .round();

  GeoPoint offset(double dLat, double dLng) =>
      GeoPoint(latitude + dLat, longitude + dLng);

  /// The point [meters] away towards compass [bearing] (0 = north).
  GeoPoint moved(double bearing, double meters) {
    final radians = bearing * math.pi / 180;
    const metresPerDegree = 111320.0;
    return GeoPoint(
      latitude + math.cos(radians) * meters / metresPerDegree,
      longitude +
          math.sin(radians) *
              meters /
              (metresPerDegree * math.cos(latitude * math.pi / 180)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'GeoPoint(${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)})';
}
