import 'dart:ui';

import '../../models/geo_point.dart';
import '../../models/route.dart';
import '../maps/mock_city.dart';
import 'route_planner.dart';

/// Offline planner over the [MockCity] road grid: leave the building onto
/// the nearest road, drive to a junction, take one corner across the grid,
/// then drive to the destination. Deterministic and network-free.
class MockRoutePlanner implements RoutePlanner {
  const MockRoutePlanner({
    this.city = const MockCity(),
    this.speedKmh = PlannedRoute.defaultSpeedKmh,
  });

  final MockCity city;
  final double speedKmh;

  @override
  Future<PlannedRoute> plan(List<GeoPoint> waypoints) async =>
      planSync(waypoints);

  PlannedRoute planSync(List<GeoPoint> waypoints) {
    if (waypoints.length < 2) {
      return PlannedRoute(
        points: waypoints,
        distanceM: 0,
        duration: Duration.zero,
      );
    }
    final world = [for (final w in waypoints) city.toWorld(w)];
    final legs = [
      for (var i = 0; i < world.length - 1; i++) _leg(world[i], world[i + 1]),
    ];

    final points = <Offset>[];
    final legStarts = <int>[];
    for (final leg in legs) {
      legStarts.add(points.isEmpty ? 0 : points.length - 1);
      points.addAll(points.isEmpty ? leg : leg.skip(1));
    }
    final geo = [for (final p in points) city.toGeo(p)];
    final path = RoutePath(geo);

    final steps = <RouteStep>[];
    for (var l = 0; l < legs.length; l++) {
      steps.addAll(
        _legSteps(
          legs[l],
          offset: legStarts[l],
          path: path,
          geo: geo,
          isLast: l == legs.length - 1,
          stop: l + 1,
        ),
      );
    }
    final distanceM = path.length.round();
    return PlannedRoute(
      points: geo,
      distanceM: distanceM,
      duration: PlannedRoute.travelTime(distanceM, speedKmh: speedKmh),
      steps: steps,
    );
  }

  List<Offset> _leg(Offset a, Offset b) {
    final aRoad = city.snapToRoad(a);
    final bRoad = city.snapToRoad(b);
    final aNode = city.nearestJunction(aRoad);
    final bNode = city.nearestJunction(bRoad);
    return _simplify([
      a,
      aRoad.point,
      aNode,
      Offset(bNode.dx, aNode.dy),
      bNode,
      bRoad.point,
      b,
    ]);
  }

  /// Drops repeated points and straight-through or U-turn middle points.
  static List<Offset> _simplify(List<Offset> raw) {
    final out = <Offset>[];
    for (final p in raw) {
      if (out.isNotEmpty && (out.last - p).distance < 1) continue;
      while (out.length >= 2 && _collinear(out[out.length - 2], out.last, p)) {
        out.removeLast();
      }
      out.add(p);
    }
    return out;
  }

  static bool _collinear(Offset a, Offset b, Offset c) {
    final u = b - a, v = c - b;
    return _cross(u, v).abs() <= 0.01 * u.distance * v.distance;
  }

  /// Positive when turning right (screen y points down).
  static double _cross(Offset u, Offset v) => u.dx * v.dy - u.dy * v.dx;

  bool _onRoad(Offset p) => (city.snapToRoad(p).point - p).distance < 1;

  static String _compass(Offset d) => d.dx.abs() > d.dy.abs()
      ? (d.dx > 0 ? 'east' : 'west')
      : (d.dy < 0 ? 'north' : 'south');

  List<RouteStep> _legSteps(
    List<Offset> leg, {
    required int offset,
    required RoutePath path,
    required List<GeoPoint> geo,
    required bool isLast,
    required int stop,
  }) {
    final m = leg.length - 1;
    final s = _onRoad(leg.first) || m < 2 ? 0 : 1;
    final e = _onRoad(leg.last) || m - 1 <= s ? m : m - 1;
    RouteStep at(int i, Maneuver maneuver, String instruction, String street) =>
        RouteStep(
          maneuver: maneuver,
          instruction: instruction,
          street: street,
          at: geo[offset + i],
          distanceFromStartM: path.distanceTo(offset + i).round(),
        );

    final steps = <RouteStep>[];
    if (e > s) {
      final street = city.streetFor(leg[s], leg[s + 1]);
      steps.add(
        at(
          0,
          Maneuver.depart,
          'Head ${_compass(leg[s + 1] - leg[s])} on $street',
          street,
        ),
      );
    } else {
      steps.add(at(0, Maneuver.depart, 'Head towards the destination', ''));
    }
    for (var i = s + 1; i < e; i++) {
      final street = city.streetFor(leg[i], leg[i + 1]);
      final right = _cross(leg[i] - leg[i - 1], leg[i + 1] - leg[i]) > 0;
      steps.add(
        at(
          i,
          right ? Maneuver.right : Maneuver.left,
          'Turn ${right ? 'right' : 'left'} onto $street',
          street,
        ),
      );
    }
    final side = e < m && e > 0
        ? (_cross(leg[e] - leg[e - 1], leg[m] - leg[e]) > 0
              ? 'on your right'
              : 'on your left')
        : 'ahead';
    steps.add(
      at(
        m,
        Maneuver.arrive,
        isLast ? 'Destination $side' : 'Stop $stop $side',
        '',
      ),
    );
    return steps;
  }
}
