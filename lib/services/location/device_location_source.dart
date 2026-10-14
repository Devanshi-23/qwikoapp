import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../models/geo_point.dart';
import 'location_source.dart';

/// Real GPS through geolocator. Not registered in the demo build.
class DeviceLocationSource implements LocationSource {
  DeviceLocationSource();

  static const LocationSettings _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  final StreamController<LocationFix> _fixes =
      StreamController<LocationFix>.broadcast();
  StreamSubscription<Position>? _subscription;
  LocationFix? _lastFix;

  @override
  Stream<LocationFix> get fixes {
    _subscription ??= Geolocator.getPositionStream(locationSettings: _settings)
        .listen(_onPosition, onError: (_) => _markLost());
    return _fixes.stream;
  }

  @override
  LocationFix? get lastFix => _lastFix;

  void _onPosition(Position p) {
    _lastFix = LocationFix(
      position: GeoPoint(p.latitude, p.longitude),
      heading: p.heading,
      at: p.timestamp,
    );
    _fixes.add(_lastFix!);
  }

  void _markLost() {
    final last = _lastFix;
    if (last == null) return;
    _lastFix = LocationFix(
      position: last.position,
      heading: last.heading,
      at: last.at,
      isLive: false,
    );
    _fixes.add(_lastFix!);
  }

  /// A one-off fix. Returns null if location is off or permission denied.
  Future<GeoPoint?> currentPosition() async {
    if (!await ensurePermission()) return null;
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: _settings)
          .timeout(const Duration(seconds: 15));
      return GeoPoint(p.latitude, p.longitude);
    } on Exception {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : GeoPoint(last.latitude, last.longitude);
    }
  }

  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Real GPS follows the rider, not a path.
  @override
  void followPath(List<GeoPoint> path) {}

  @override
  void stop() {}

  @override
  void dispose() {
    _subscription?.cancel();
    _fixes.close();
  }
}
