import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../core/failures.dart';
import '../core/formatters.dart';
import '../models/geo_point.dart';
import '../models/order.dart';
import '../models/route.dart';
import '../models/trip.dart';
import '../services/location/location_source.dart';
import '../services/maps/map_view_model.dart';
import '../services/routing/route_planner.dart';
import 'active_trip_controller.dart';
import 'device_controller.dart';

enum RouteStatus {
  idle,
  calculating,
  ready,

  /// Re-planning after the rider left the route.
  recalculating,

  /// Routing failed; showing a straight-line estimate.
  unavailable,
}

/// The leg being driven: from the last stop to the store or a customer.
class NavigationLeg {
  const NavigationLeg({
    required this.key,
    required this.from,
    required this.to,
    required this.toStore,
    required this.name,
    required this.arrived,
  });

  final String key;
  final GeoPoint from;
  final GeoPoint to;
  final bool toStore;
  final String name;

  /// The rider has marked arrival for this leg.
  final bool arrived;
}

/// Where the rider is on the current leg: route, progress, ETA and the next
/// manoeuvre. Knows about trips; the map it produces does not.
class NavigationController extends ChangeNotifier {
  NavigationController({
    required this._planner,
    required this._location,
    required this._trip,
    required this._device,
    required this._clock,
    this.simulation,
  }) {
    _trip.addListener(_onTrip);
    _device.addListener(_onDevice);
    _fixes = _location.fixes.listen(_onFix);
    _onTrip();
  }

  /// How far the rider is pushed off the route by "Simulate deviation".
  static const double deviationM = 120;

  /// Within this distance of the destination counts as arrived.
  static const double arrivalRadiusM = 15;

  final RoutePlanner _planner;
  final LocationSource _location;
  final ActiveTripController _trip;
  final DeviceController _device;
  final Clock _clock;

  /// Present in demo builds only.
  final LocationSimulation? simulation;

  late final StreamSubscription<LocationFix> _fixes;
  NavigationLeg? _leg;
  String? _tripId;
  PlannedRoute? _route;
  RoutePath? _path;
  List<GeoPoint> _upcoming = const [];
  double _travelledM = 0;
  RouteStatus _status = RouteStatus.idle;
  String? _error;
  LocationFix? _fix;
  bool _muted = false;
  int _generation = 0;
  bool _disposed = false;

  RouteStatus get status => _status;

  bool get isPlanning =>
      _status == RouteStatus.calculating ||
      _status == RouteStatus.recalculating;

  NavigationLeg? get leg => _leg;

  PlannedRoute? get route => _route;

  /// Why the route is a straight-line estimate.
  String? get error => _error;

  bool get muted => _muted;

  bool get permissionDenied => !_device.locationPermissionGranted;

  bool get serviceOff => !_device.locationServiceEnabled;

  /// No position updates arrive while location is blocked.
  bool get locationBlocked => !_device.canLocate;

  bool get gpsLost => _fix != null && !_fix!.isLive;

  /// When the last position report arrived.
  DateTime? get lastFixAt => _fix?.at;

  GeoPoint? get position => _fix?.position ?? _leg?.from;

  double get heading => _fix?.heading ?? 0;

  double get travelledM => _travelledM;

  int? get remainingM {
    final path = _path;
    if (path == null) return null;
    return math.max(0, path.length - _travelledM).round();
  }

  Duration? get eta {
    final remaining = remainingM;
    return remaining == null ? null : PlannedRoute.travelTime(remaining);
  }

  DateTime? get arrivalTime {
    final left = eta;
    return left == null ? null : _clock.now().add(left);
  }

  bool get arrived {
    final leg = _leg;
    if (leg == null) return false;
    if (leg.arrived) return true;
    final remaining = remainingM;
    return remaining != null && remaining <= arrivalRadiusM;
  }

  /// Steps still ahead, the next manoeuvre first.
  List<RouteStep> get upcomingSteps {
    final steps = _route?.steps ?? const <RouteStep>[];
    return [
      for (final s in steps)
        if (s.distanceFromStartM > _travelledM + 5 ||
            s.maneuver == Maneuver.arrive)
          s,
    ];
  }

  RouteStep? get nextStep {
    final ahead = upcomingSteps;
    return ahead.isEmpty ? null : ahead.first;
  }

  int? get distanceToNextStepM {
    final step = nextStep;
    if (step == null) return null;
    return math.max(0, step.distanceFromStartM - _travelledM).round();
  }

  /// "8 min · 2.3 km · Arrive by 3:42 PM", or null while planning.
  String? get summary {
    final remaining = remainingM, left = eta, at = arrivalTime;
    if (remaining == null || left == null || at == null || isPlanning) {
      return null;
    }
    return '${formatMinutes(left)} · ${formatDistance(remaining)} · '
        'Arrive by ${formatTime(at)}';
  }

  void toggleMute() {
    _muted = !_muted;
    _notify();
  }

  /// Plans the current leg again, for example after a failure.
  Future<void> retry() async {
    final leg = _leg;
    if (leg == null) return;
    await _plan(leg, from: position ?? leg.from);
  }

  /// Demo: pushes the rider off the route and recalculates from there.
  Future<void> simulateDeviation() async {
    final leg = _leg;
    final from = position;
    if (leg == null || from == null || leg.arrived) return;
    final off = from.moved(heading + 90, deviationM);
    simulation?.teleport(off);
    await _plan(leg, from: off, recalculating: true);
  }

  /// Demo: puts the rider at the end of the current leg, even while the
  /// route is still being planned.
  void jumpToDestination() {
    final leg = _leg;
    final sim = simulation;
    if (leg == null || sim == null || leg.arrived) return;
    if (_path != null && !isPlanning) {
      sim.jumpToEnd();
    } else {
      sim.teleport(leg.to);
    }
  }

  NavigationLeg? _legFor(DeliveryTrip trip) {
    final task = trip.currentTask;
    final index = trip.currentTaskIndex;
    final previous = index == 0
        ? trip.store.location
        : trip.tasks[index - 1].customer.location;
    return switch (task.status) {
      OrderStatus.accepted ||
      OrderStatus.headingToStore ||
      OrderStatus.arrivedAtStore => NavigationLeg(
        key: '${trip.id}:store',
        from: trip.startPosition,
        to: trip.store.location,
        toStore: true,
        name: trip.store.name,
        arrived: task.status == OrderStatus.arrivedAtStore,
      ),
      OrderStatus.returningToStore => NavigationLeg(
        key: '${trip.id}:return',
        from: trip.tasks.last.customer.location,
        to: trip.store.location,
        toStore: true,
        name: trip.store.name,
        arrived: false,
      ),
      OrderStatus.pickedUp ||
      OrderStatus.headingToCustomer ||
      OrderStatus.arrivedAtCustomer => NavigationLeg(
        key:
            '${trip.id}:$index:customer:'
            '${task.customer.location.latitude},'
            '${task.customer.location.longitude}',
        from: previous,
        to: task.customer.location,
        toStore: false,
        name: task.customer.fullName,
        arrived: task.status == OrderStatus.arrivedAtCustomer,
      ),
      _ => null,
    };
  }

  /// Stops after the current leg, drawn as the upcoming route.
  List<GeoPoint> _laterStops(DeliveryTrip trip, NavigationLeg leg) => [
    leg.to,
    for (final t in trip.tasks.skip(
      leg.toStore ? 0 : trip.currentTaskIndex + 1,
    ))
      if (!t.status.isFinal) t.customer.location,
  ];

  void _onTrip() {
    final trip = _trip.trip;
    final leg = trip == null || trip.cancellation != null
        ? null
        : _legFor(trip);
    if (trip == null || leg == null) {
      if (_leg != null) _clear();
      return;
    }
    final previous = _leg;
    _leg = leg;
    if (previous?.key != leg.key) {
      final newTrip = _tripId != trip.id;
      _tripId = trip.id;
      // Re-routes (the customer moved their pin) and the trip back to the
      // store start where the rider is.
      final fromHere =
          !newTrip &&
          (leg.key.endsWith(':return') ||
              (previous != null &&
                  !previous.toStore &&
                  !leg.toStore &&
                  previous.from == leg.from));
      final here = position;
      final start = fromHere && here != null
          ? here
          : simulation != null || newTrip || here == null
          ? leg.from
          : here;
      if (simulation != null && start == leg.from) simulation!.teleport(start);
      unawaited(_plan(leg, from: start, laterStops: _laterStops(trip, leg)));
      return;
    }
    if (leg.arrived && !(previous?.arrived ?? false)) {
      simulation?.jumpToEnd();
      final path = _path;
      if (path != null) _travelledM = path.length;
    }
    _notify();
  }

  Future<void> _plan(
    NavigationLeg leg, {
    required GeoPoint from,
    bool recalculating = false,
    List<GeoPoint>? laterStops,
  }) async {
    final generation = ++_generation;
    _status = recalculating
        ? RouteStatus.recalculating
        : RouteStatus.calculating;
    _error = null;
    if (!recalculating) {
      _route = null;
      _path = null;
    }
    _notify();

    PlannedRoute route;
    String? error;
    try {
      route = await _planner.plan([from, leg.to]);
    } on AppFailure catch (failure) {
      route = PlannedRoute.straightLine([from, leg.to]);
      error = failure.message;
    }
    if (_disposed || generation != _generation) return;

    _route = route;
    _path = RoutePath(route.points);
    _travelledM = 0;
    _error = error;
    _status = error == null ? RouteStatus.ready : RouteStatus.unavailable;
    final here = _fix?.position;
    final alreadyThere =
        here != null && here.distanceMetersTo(leg.to) <= arrivalRadiusM;
    if (leg.arrived || alreadyThere) {
      _travelledM = _path!.length;
    } else {
      _location.followPath(route.points);
    }
    _notify();

    final stops = laterStops;
    if (stops != null) unawaited(_planLater(stops, generation));
  }

  Future<void> _planLater(List<GeoPoint> stops, int generation) async {
    if (stops.length < 2) {
      _upcoming = const [];
      return;
    }
    List<GeoPoint> points;
    try {
      points = (await _planner.plan(stops)).points;
    } on AppFailure {
      points = stops;
    }
    if (_disposed || generation != _generation) return;
    _upcoming = points;
    _notify();
  }

  void _onFix(LocationFix fix) {
    if (locationBlocked) return;
    _fix = fix;
    final path = _path;
    if (path != null && fix.isLive && !isPlanning) {
      _travelledM = math.max(_travelledM, path.locate(fix.position));
    }
    _notify();
  }

  void _onDevice() {
    if (!locationBlocked) {
      final latest = _location.lastFix;
      if (latest != null) _onFix(latest);
    }
    _notify();
  }

  void _clear() {
    _generation++;
    _leg = null;
    _tripId = null;
    _route = null;
    _path = null;
    _upcoming = const [];
    _travelledM = 0;
    _status = RouteStatus.idle;
    _error = null;
    _location.stop();
    _notify();
  }

  /// The trip as pure map data.
  MapViewModel get mapModel {
    final trip = _trip.trip;
    final leg = _leg;
    if (trip == null || leg == null) return const MapViewModel();
    final rider = position;
    final path = _path;
    final multiDrop = trip.tasks.length > 1;
    final (done, ahead) = path == null
        ? (const <GeoPoint>[], const <GeoPoint>[])
        : path.splitAt(_travelledM);

    final summaryText = summary;
    return MapViewModel(
      focus: rider,
      markers: [
        if (rider != null)
          MapMarker(
            id: 'rider',
            kind: MapMarkerKind.rider,
            position: rider,
            heading: heading,
            label: gpsLost ? 'You (last known)' : 'You',
          ),
        MapMarker(
          id: 'store',
          kind: MapMarkerKind.store,
          position: trip.store.location,
          label: trip.store.name,
        ),
        for (final (i, task) in trip.tasks.indexed)
          if (!task.status.isFinal)
            MapMarker(
              id: 'customer-${task.displayId}',
              kind: MapMarkerKind.customer,
              position: task.customer.location,
              label: task.customer.fullName,
              badge: multiDrop ? '${i + 1}' : null,
            ),
      ],
      polylines: [
        if (_upcoming.length > 1)
          MapPolyline(points: _upcoming, style: MapLineStyle.upcoming),
        if (done.length > 1)
          MapPolyline(points: done, style: MapLineStyle.travelled),
        if (ahead.length > 1)
          MapPolyline(
            points: ahead,
            style: _route?.isFallback ?? false
                ? MapLineStyle.fallback
                : MapLineStyle.route,
          ),
      ],
      semanticLabel:
          'Map. Route to ${leg.name}'
          '${summaryText == null ? '' : ', $summaryText'}.',
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _trip.removeListener(_onTrip);
    _device.removeListener(_onDevice);
    _fixes.cancel();
    super.dispose();
  }
}
