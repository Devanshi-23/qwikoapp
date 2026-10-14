import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/models/geo_point.dart';
import 'package:qwiko_delivery_agent/models/route.dart';
import 'package:qwiko_delivery_agent/services/location/location_source.dart';
import 'package:qwiko_delivery_agent/services/location/simulated_location_source.dart';
import 'package:qwiko_delivery_agent/services/maps/mock_city.dart';
import 'package:qwiko_delivery_agent/services/routing/mock_route_planner.dart';

void main() {
  const city = MockCity();
  const planner = MockRoutePlanner();
  const from = GeoPoint(28.6012, 77.2031);
  const to = GeoPoint(28.6195, 77.2264);

  group('MockRoutePlanner', () {
    test('is deterministic', () {
      final a = planner.planSync([from, to]);
      final b = planner.planSync([from, to]);
      expect(a.points, b.points);
      expect(a.distanceM, b.distanceM);
      expect(
        a.steps.map((s) => s.instruction),
        b.steps.map((s) => s.instruction),
      );
    });

    test('drives along grid roads between the building connectors', () {
      final route = planner.planSync([from, to]);
      final world = route.points.map(city.toWorld).toList();
      expect(world.length, greaterThan(3));
      for (var i = 1; i < world.length - 2; i++) {
        final d = world[i + 1] - world[i];
        expect(
          d.dx.abs() < 0.5 || d.dy.abs() < 0.5,
          isTrue,
          reason: 'segment $i is not axis-aligned: $d',
        );
      }
      expect(route.points.first, from);
      expect(route.points.last, to);
      expect(route.isFallback, isFalse);
    });

    test('is at least the straight-line distance and timed at 18 km/h', () {
      final route = planner.planSync([from, to]);
      expect(route.distanceM, greaterThanOrEqualTo(from.distanceMetersTo(to)));
      expect(route.distanceM, RoutePath(route.points).length.round());
      final expected = route.distanceM / (18 / 3.6);
      expect(route.duration.inSeconds, closeTo(expected, 1));
    });

    test('gives turn-by-turn steps with street names', () {
      final route = planner.planSync([from, to]);
      final steps = route.steps;
      expect(steps.first.maneuver, Maneuver.depart);
      expect(steps.first.instruction, startsWith('Head '));
      expect(steps.last.maneuver, Maneuver.arrive);
      expect(steps.last.instruction, startsWith('Destination '));
      expect(steps.last.distanceFromStartM, route.distanceM);
      final turns = steps.where(
        (s) => s.maneuver == Maneuver.left || s.maneuver == Maneuver.right,
      );
      expect(turns, isNotEmpty);
      for (final turn in turns) {
        expect(turn.instruction, matches(RegExp(r'^Turn (left|right) onto ')));
        expect(turn.street, isNotEmpty);
      }
      for (var i = 1; i < steps.length; i++) {
        expect(
          steps[i].distanceFromStartM,
          greaterThanOrEqualTo(steps[i - 1].distanceFromStartM),
        );
      }
    });

    test('plans multi-stop routes with an arrival per stop', () {
      const third = GeoPoint(28.6101, 77.2402);
      final route = planner.planSync([from, to, third]);
      final arrivals = route.steps.where((s) => s.maneuver == Maneuver.arrive);
      expect(arrivals.map((s) => s.instruction.split(' ').first), [
        'Stop',
        'Destination',
      ]);
      expect(route.points.last, third);
    });

    test('straight-line fallback is marked and timed', () {
      final route = PlannedRoute.straightLine([from, to]);
      expect(route.isFallback, isTrue);
      expect(route.points, [from, to]);
      expect(route.distanceM, closeTo(from.distanceMetersTo(to), 1));
    });
  });

  group('RoutePath', () {
    final path = RoutePath(planner.planSync([from, to]).points);

    test('locates points it produced', () {
      for (final d in [0.0, 120.0, path.length / 2, path.length]) {
        expect(path.locate(path.pointAt(d)), closeTo(d, 2));
      }
    });

    test('splits into travelled and remaining parts', () {
      final (done, ahead) = path.splitAt(300);
      expect(done.first, path.points.first);
      expect(ahead.last, path.points.last);
      expect(done.last, ahead.first);
      expect(RoutePath(done).length, closeTo(300, 1));
    });
  });

  group('SimulatedLocationSource', () {
    late FakeClock clock;
    late SimulatedLocationSource source;
    late List<LocationFix> fixes;
    final route = planner.planSync([from, to]);
    final path = RoutePath(route.points);

    setUp(() {
      clock = FakeClock(DateTime(2026, 10, 13, 14));
      source = SimulatedLocationSource(clock: clock, start: from);
      fixes = [];
      source.fixes.listen(fixes.add);
    });

    tearDown(() => source.dispose());

    double travelled() => path.locate(source.lastFix!.position);

    test('moves along the path at 18 km/h by the clock', () {
      source.followPath(route.points);
      expect(fixes.single.position, from);

      clock.advance(const Duration(seconds: 20));
      source.advance();
      expect(travelled(), closeTo(100, 2));
      expect(source.lastFix!.isLive, isTrue);
    });

    test('pauses, resumes and jumps to the end', () {
      source.followPath(route.points);
      source.pause();
      clock.advance(const Duration(minutes: 1));
      source.advance();
      expect(travelled(), 0);

      source.resume();
      clock.advance(const Duration(seconds: 10));
      source.advance();
      expect(travelled(), closeTo(50, 2));

      source.jumpToEnd();
      expect(source.lastFix!.position, to);
      expect(source.isMoving, isFalse);
    });

    test('losing GPS reports the last known position, then recovers', () {
      source.followPath(route.points);
      clock.advance(const Duration(seconds: 10));
      source.advance();
      final known = source.lastFix!.position;

      source.loseSignal();
      expect(source.signalLost, isTrue);
      expect(source.lastFix!.isLive, isFalse);
      expect(source.lastFix!.position, known);

      clock.advance(const Duration(seconds: 10));
      source.advance();
      expect(source.lastFix!.position, known);

      clock.advance(const Duration(seconds: 11));
      source.advance();
      expect(source.signalLost, isFalse);
      expect(source.lastFix!.isLive, isTrue);
      expect(travelled(), closeTo(155, 3));
    });
  });
}
