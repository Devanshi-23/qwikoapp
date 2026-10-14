import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'geo_point.dart';

enum Maneuver { depart, left, right, straight, arrive }

/// One turn-by-turn instruction, placed where the manoeuvre happens.
class RouteStep {
  const RouteStep({
    required this.maneuver,
    required this.instruction,
    required this.at,
    required this.distanceFromStartM,
    this.street = '',
  });

  final Maneuver maneuver;

  /// For example "Turn left onto Ring Road".
  final String instruction;
  final String street;
  final GeoPoint at;
  final int distanceFromStartM;

  @override
  String toString() => 'RouteStep($instruction @ ${distanceFromStartM}m)';
}

/// A route from a planner. [isFallback] routes are straight lines drawn
/// when real routing failed.
class PlannedRoute {
  const PlannedRoute({
    required this.points,
    required this.distanceM,
    required this.duration,
    this.steps = const [],
    this.isFallback = false,
  });

  /// Straight lines between [waypoints], timed at [speedKmh].
  factory PlannedRoute.straightLine(
    List<GeoPoint> waypoints, {
    double speedKmh = defaultSpeedKmh,
  }) {
    final distanceM = RoutePath(waypoints).length.round();
    return PlannedRoute(
      points: waypoints,
      distanceM: distanceM,
      duration: travelTime(distanceM, speedKmh: speedKmh),
      isFallback: true,
      steps: [
        if (waypoints.length > 1)
          RouteStep(
            maneuver: Maneuver.arrive,
            instruction: 'Head towards the destination',
            at: waypoints.last,
            distanceFromStartM: distanceM,
          ),
      ],
    );
  }

  /// Average two-wheeler speed in city traffic.
  static const double defaultSpeedKmh = 18;

  static Duration travelTime(
    num distanceM, {
    double speedKmh = defaultSpeedKmh,
  }) => Duration(seconds: (distanceM / (speedKmh / 3.6)).round());

  final List<GeoPoint> points;
  final int distanceM;
  final Duration duration;
  final List<RouteStep> steps;
  final bool isFallback;
}

/// A polyline with distances along it, for progress and interpolation.
class RoutePath {
  RoutePath(this.points) : _cumulative = _cumulate(points);

  static const Distance _distance = Distance();

  final List<GeoPoint> points;
  final List<double> _cumulative;

  static List<double> _cumulate(List<GeoPoint> points) {
    final result = <double>[0];
    for (var i = 1; i < points.length; i++) {
      result.add(
        result.last +
            _distance.as(
              LengthUnit.Meter,
              points[i - 1].toLatLng(),
              points[i].toLatLng(),
            ),
      );
    }
    return result;
  }

  double get length => _cumulative.last;

  /// Distance from the start to `points[index]`.
  double distanceTo(int index) => _cumulative[index];

  int _segmentAt(double distance) {
    for (var i = 1; i < _cumulative.length; i++) {
      if (distance <= _cumulative[i]) return i - 1;
    }
    return math.max(0, points.length - 2);
  }

  /// The point [distance] metres along the path.
  GeoPoint pointAt(double distance) {
    if (points.length < 2) return points.first;
    final d = distance.clamp(0, length).toDouble();
    final i = _segmentAt(d);
    final span = _cumulative[i + 1] - _cumulative[i];
    final t = span == 0 ? 0.0 : (d - _cumulative[i]) / span;
    final a = points[i], b = points[i + 1];
    return GeoPoint(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// The path before and after [distance], both including the split point.
  (List<GeoPoint>, List<GeoPoint>) splitAt(double distance) {
    if (points.length < 2) return (points, points);
    final d = distance.clamp(0, length).toDouble();
    final i = _segmentAt(d);
    final at = pointAt(d);
    return ([...points.take(i + 1), at], [at, ...points.skip(i + 1)]);
  }

  /// Compass heading in degrees (0 = north, 90 = east) at [distance].
  double headingAt(double distance) {
    if (points.length < 2) return 0;
    final i = _segmentAt(distance.clamp(0, length).toDouble());
    return bearing(points[i], points[i + 1]);
  }

  /// How far along the path the closest point to [position] is.
  double locate(GeoPoint position) {
    if (points.length < 2) return 0;
    var best = double.infinity;
    var along = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final scale = math.cos(a.latitude * math.pi / 180);
      final abx = (b.longitude - a.longitude) * scale;
      final aby = b.latitude - a.latitude;
      final apx = (position.longitude - a.longitude) * scale;
      final apy = position.latitude - a.latitude;
      final lengthSquared = abx * abx + aby * aby;
      final t = lengthSquared == 0
          ? 0.0
          : ((apx * abx + apy * aby) / lengthSquared).clamp(0.0, 1.0);
      final dx = apx - abx * t, dy = apy - aby * t;
      final gap = dx * dx + dy * dy;
      if (gap < best) {
        best = gap;
        along = _cumulative[i] + (_cumulative[i + 1] - _cumulative[i]) * t;
      }
    }
    return along;
  }

  static double bearing(GeoPoint from, GeoPoint to) {
    final degrees = _distance.bearing(from.toLatLng(), to.toLatLng());
    return (degrees + 360) % 360;
  }
}
