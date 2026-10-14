import '../../models/geo_point.dart';
import '../../models/route.dart';

/// Turns waypoints into a drivable route. The demo uses the offline
/// `MockRoutePlanner`; `GoogleRoutePlanner` can replace it later.
abstract interface class RoutePlanner {
  /// Throws an `AppFailure` when no route can be found; callers fall back
  /// to [PlannedRoute.straightLine].
  Future<PlannedRoute> plan(List<GeoPoint> waypoints);
}
