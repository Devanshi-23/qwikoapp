import 'dart:math' as math;
import 'dart:ui';

import '../../models/geo_point.dart';

/// Which way a grid road runs.
enum RoadAxis {
  /// North–south roads, at a fixed x.
  vertical,

  /// East–west roads, at a fixed y.
  horizontal,
}

/// A point snapped onto the road grid and the road it lies on.
class RoadPoint {
  const RoadPoint(this.point, this.axis);

  final Offset point;
  final RoadAxis axis;
}

/// The seeded, fully offline city behind the mock map and the mock route
/// planner: a road grid (a major road every [majorEvery] blocks) with
/// street names, plus a park and a river for the map to draw.
///
/// World coordinates are metres from [anchor] with x growing east and y
/// growing south (screen direction), using a local equirectangular
/// projection.
class MockCity {
  const MockCity({this.seed = 7, this.anchor = const GeoPoint(28.6, 77.2)});

  static const double blockM = 250;
  static const int majorEvery = 4;
  static const double _metresPerDegree = 111320;

  static const List<String> _majorNames = [
    'Ring Road',
    'Mathura Road',
    'Aurobindo Marg',
    'Lodhi Road',
    'Outer Circle',
    'Ajmal Khan Road',
    'Pusa Road',
    'Link Road',
    'Barakhamba Road',
    'Janpath',
    'Press Enclave Road',
    'Bhishma Pitamah Marg',
  ];

  static const List<String> _minorNames = [
    'Church Lane',
    'Market Road',
    'Temple Street',
    'School Lane',
    'Park Street',
    'Station Road',
    'Bank Street',
    'Mill Road',
    'Canal Road',
    'Garden Lane',
    'Library Road',
    'Bazaar Street',
    'Gurdwara Road',
    'Hospital Lane',
  ];

  final int seed;
  final GeoPoint anchor;

  double get _metresPerDegreeLng =>
      _metresPerDegree * math.cos(anchor.latitude * math.pi / 180);

  Offset toWorld(GeoPoint p) => Offset(
    (p.longitude - anchor.longitude) * _metresPerDegreeLng,
    (anchor.latitude - p.latitude) * _metresPerDegree,
  );

  GeoPoint toGeo(Offset w) => GeoPoint(
    anchor.latitude - w.dy / _metresPerDegree,
    anchor.longitude + w.dx / _metresPerDegreeLng,
  );

  static int roadIndex(double coordinate) => (coordinate / blockM).round();

  static bool isMajor(int index) => index % majorEvery == 0;

  String streetName(RoadAxis axis, int index) {
    final names = isMajor(index) ? _majorNames : _minorNames;
    final salt = axis == RoadAxis.vertical ? 3 : 11;
    final i = (index * 7 + seed * salt) % names.length;
    return names[(i + names.length) % names.length];
  }

  /// The road a segment between two grid points runs along.
  String streetFor(Offset from, Offset to) {
    final vertical = (to.dx - from.dx).abs() < (to.dy - from.dy).abs();
    return vertical
        ? streetName(RoadAxis.vertical, roadIndex(from.dx))
        : streetName(RoadAxis.horizontal, roadIndex(from.dy));
  }

  /// The closest point on any road.
  RoadPoint snapToRoad(Offset w) {
    final onVertical = Offset(roadIndex(w.dx) * blockM, w.dy);
    final onHorizontal = Offset(w.dx, roadIndex(w.dy) * blockM);
    return (w - onVertical).distance <= (w - onHorizontal).distance
        ? RoadPoint(onVertical, RoadAxis.vertical)
        : RoadPoint(onHorizontal, RoadAxis.horizontal);
  }

  /// The nearest junction reached by driving along [road].
  Offset nearestJunction(RoadPoint road) => road.axis == RoadAxis.vertical
      ? Offset(road.point.dx, roadIndex(road.point.dy) * blockM)
      : Offset(roadIndex(road.point.dx) * blockM, road.point.dy);

  int _hash(int a, int b) {
    var h = a * 73856093 ^ b * 19349663 ^ seed * 83492791;
    h = (h ^ (h >> 13)) * 1274126177;
    return (h ^ (h >> 16)) & 0x7fffffff;
  }

  /// Blocks drawn as parks.
  bool isPark(int column, int row) => _hash(column, row) % 17 == 0;

  /// Centre line of the river at world x, flowing west to east.
  double riverY(double x) =>
      2600 + 900 * math.sin(x / 2300 + seed) + 250 * math.sin(x / 700);

  static const double riverWidthM = 140;
}
