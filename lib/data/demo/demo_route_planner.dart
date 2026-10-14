import '../../core/failures.dart';
import '../../models/geo_point.dart';
import '../../models/route.dart';
import '../../services/routing/mock_route_planner.dart';
import '../../services/routing/route_planner.dart';
import 'demo_engine.dart';

/// The offline grid planner behind the demo engine, so "Next route
/// unavailable" can inject a failure. Works in airplane mode.
class DemoRoutePlanner implements RoutePlanner {
  DemoRoutePlanner({
    required this._engine,
    this._planner = const MockRoutePlanner(),
  });

  final DemoEngine _engine;
  final MockRoutePlanner _planner;

  @override
  Future<PlannedRoute> plan(List<GeoPoint> waypoints) async {
    try {
      return await _engine.run(
        OperationType.planRoute,
        () => _planner.planSync(waypoints),
      );
    } on ServerFailure {
      throw const ServerFailure("Couldn't calculate a route.");
    }
  }
}
