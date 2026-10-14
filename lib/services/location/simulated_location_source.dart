import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../models/geo_point.dart';
import '../../models/route.dart';
import 'location_source.dart';

/// Moves the rider along a path at demo speed. Time comes from the [Clock],
/// so the demo clock's speed multiplier (1×, 2×, 5×) speeds riders up too.
class SimulatedLocationSource implements LocationSource, LocationSimulation {
  SimulatedLocationSource({
    required this._clock,
    GeoPoint start = const GeoPoint(28.6, 77.2),
    this.speedKmh = PlannedRoute.defaultSpeedKmh,
    this.tick = const Duration(milliseconds: 500),
    this.gpsLostFor = const Duration(seconds: 20),
  }) : _position = start,
       _lastTick = _clock.now();

  final Clock _clock;
  final double speedKmh;
  final Duration tick;
  final Duration gpsLostFor;

  final StreamController<LocationFix> _fixes =
      StreamController<LocationFix>.broadcast(sync: true);

  GeoPoint _position;
  double _heading = 0;
  RoutePath? _path;
  double _travelled = 0;
  bool _paused = false;
  DateTime? _lostUntil;
  DateTime _lastTick;
  LocationFix? _lastFix;
  Timer? _timer;

  @override
  Stream<LocationFix> get fixes => _fixes.stream;

  @override
  LocationFix? get lastFix => _lastFix;

  /// The true position, even while the signal is lost.
  GeoPoint get position => _position;

  @override
  bool get isPaused => _paused;

  @override
  bool get signalLost => _lostUntil != null;

  bool get isMoving => _path != null && !_paused && _travelled < _path!.length;

  @override
  void followPath(List<GeoPoint> path) {
    if (path.length < 2) {
      teleport(path.isEmpty ? _position : path.first);
      return;
    }
    _path = RoutePath(path);
    _travelled = 0;
    _position = path.first;
    _heading = _path!.headingAt(0);
    _lastTick = _clock.now();
    _emit();
    _ensureTimer();
  }

  @override
  void stop() {
    _path = null;
    _syncTimer();
  }

  @override
  void teleport(GeoPoint position) {
    _path = null;
    _position = position;
    _emit();
    _syncTimer();
  }

  @override
  void pause() {
    if (_paused) return;
    advance();
    _paused = true;
    _syncTimer();
  }

  @override
  void resume() {
    if (!_paused) return;
    _paused = false;
    _lastTick = _clock.now();
    _ensureTimer();
  }

  @override
  void jumpToEnd() {
    final path = _path;
    if (path == null) return;
    _travelled = path.length;
    _position = path.points.last;
    _emit();
    _syncTimer();
  }

  @override
  void loseSignal([Duration? duration]) {
    _lostUntil = _clock.now().add(duration ?? gpsLostFor);
    final last = _lastFix;
    _lastFix = LocationFix(
      position: last?.position ?? _position,
      heading: last?.heading ?? _heading,
      at: last?.at ?? _clock.now(),
      isLive: false,
    );
    _fixes.add(_lastFix!);
    _ensureTimer();
  }

  /// Advances the simulation to the clock's current time. Runs on a timer;
  /// tests call it directly after moving a fake clock.
  @visibleForTesting
  void advance() {
    final now = _clock.now();
    final elapsed = now.difference(_lastTick);
    _lastTick = now;

    var recovered = false;
    if (_lostUntil != null && !now.isBefore(_lostUntil!)) {
      _lostUntil = null;
      recovered = true;
    }
    var moved = false;
    final path = _path;
    if (path != null && !_paused && _travelled < path.length) {
      final step = speedKmh / 3.6 * elapsed.inMilliseconds / 1000;
      _travelled = math.min(path.length, _travelled + step);
      _position = path.pointAt(_travelled);
      _heading = path.headingAt(_travelled);
      moved = step > 0;
    }
    if (moved || recovered) _emit();
    _syncTimer();
  }

  void _emit() {
    if (_lostUntil != null) return;
    _lastFix = LocationFix(
      position: _position,
      heading: _heading,
      at: _clock.now(),
    );
    _fixes.add(_lastFix!);
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(tick, (_) => advance());
  }

  void _syncTimer() {
    if (isMoving || signalLost) {
      _ensureTimer();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _fixes.close();
  }
}
