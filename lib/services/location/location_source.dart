import '../../models/geo_point.dart';

/// One position report.
class LocationFix {
  const LocationFix({
    required this.position,
    required this.at,
    this.heading = 0,
    this.isLive = true,
  });

  final GeoPoint position;

  /// Compass degrees, 0 = north.
  final double heading;
  final DateTime at;

  /// False while the signal is lost and this is the last known position.
  final bool isLive;
}

/// Where the rider is. The demo uses `SimulatedLocationSource`; a live build
/// would use `DeviceLocationSource`.
abstract interface class LocationSource {
  /// Broadcast stream of fixes.
  Stream<LocationFix> get fixes;

  LocationFix? get lastFix;

  /// Simulated sources move along [path]; device sources ignore it.
  void followPath(List<GeoPoint> path);

  /// Stops moving and holds the current position.
  void stop();

  void dispose();
}

/// Extra controls only a simulated source supports.
abstract interface class LocationSimulation {
  bool get isPaused;

  void pause();

  void resume();

  /// Moves straight to the end of the current path.
  void jumpToEnd();

  /// Places the rider at [position] without following a path.
  void teleport(GeoPoint position);

  /// Stops reporting fixes for [duration] (or the default), then recovers.
  void loseSignal([Duration? duration]);

  bool get signalLost;
}
