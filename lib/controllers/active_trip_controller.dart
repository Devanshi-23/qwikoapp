import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../core/domain_events.dart';
import '../core/failures.dart';
import '../data/repositories/trip_repository.dart';
import '../models/geo_point.dart';
import '../models/media_ref.dart';
import '../models/order.dart';
import '../models/store_issue.dart';
import '../models/trip.dart';

/// The rider's current trip, if any. Owns the delivery steps from heading
/// to the store through completing each drop, and enforces their order:
/// every step goes through the repository, which records an [OrderEvent].
class ActiveTripController extends ChangeNotifier {
  ActiveTripController({
    required this._repository,
    required DomainEventBus events,
    required this._clock,
    GeoPoint? Function()? position,
  }) : _position = position ?? (() => null) {
    _subscription = events.stream.listen((event) {
      if (event is DataReset) {
        reset();
      } else if (event is TripChanged) {
        unawaited(_reload());
      }
    });
  }

  final TripRepository _repository;
  final Clock _clock;

  /// The rider's location for geofenced steps; null when it's unknown or
  /// location is off.
  final GeoPoint? Function() _position;
  late final StreamSubscription<DomainEvent> _subscription;

  DeliveryTrip? _trip;
  bool _busy = false;
  bool _disposed = false;

  DeliveryTrip? get trip => _trip;

  bool get hasTrip => _trip != null;

  /// True while a step is being saved; screens disable the step button.
  bool get isBusy => _busy;

  DeliveryTask? get currentTask => _trip?.currentTask;

  /// Set when the trip ended before pickup; the screen shows the reason and
  /// compensation until the rider acknowledges.
  TripCancellation? get cancellation => _trip?.cancellation;

  DateTime get now => _clock.now();

  /// Distance to the store, or null when the rider's location is unknown.
  int? get distanceToStoreM {
    final trip = _trip;
    final here = _position();
    if (trip == null || here == null) return null;
    return here.distanceMetersTo(trip.store.location).round();
  }

  bool get isNearStore {
    final distance = distanceToStoreM;
    return distance != null && distance <= DeliveryTrip.pickupGeofenceM;
  }

  /// Distance to the current customer, or null when it's unknown.
  int? get distanceToCustomerM {
    final task = currentTask;
    final here = _position();
    if (task == null || here == null) return null;
    return here.distanceMetersTo(task.customer.location).round();
  }

  bool get isNearCustomer {
    final distance = distanceToCustomerM;
    return distance != null && distance <= DeliveryTask.customerGeofenceM;
  }

  /// What the rider earned on the current (or just finished) trip.
  int get tripEarnedPaise =>
      _finished.values.fold(0, (sum, t) => sum + t.earnedPaise);

  /// Orders of the current (or just finished) trip that reached an end
  /// state.
  List<DeliveryTask> get tripFinished => _finished.values.toList();

  final Map<String, DeliveryTask> _finished = {};
  String? _finishedTripId;

  void _track(
    DeliveryTrip? trip, [
    Iterable<DeliveryTask> finished = const [],
  ]) {
    if (trip != null && trip.id != _finishedTripId) {
      _finishedTripId = trip.id;
      _finished.clear();
    }
    for (final task in [...?trip?.tasks, ...finished]) {
      if (task.status.isFinal) _finished[task.orderId] = task;
    }
  }

  void setTrip(DeliveryTrip? trip) {
    _trip = trip;
    _track(trip);
    _notify();
  }

  /// Picks up a trip that was active before the app restarted.
  Future<void> restore() async => setTrip(await _repository.activeTrip());

  /// The saved trip changed elsewhere, for example a cancellation or an
  /// offline step that synced.
  Future<void> _reload() async {
    try {
      final saved = await _repository.activeTrip();
      if (_disposed || saved == _trip) return;
      _trip = saved;
      _track(saved);
      _notify();
    } on AppFailure {
      // Keep showing the last known trip.
    }
  }

  DeliveryTrip _requireTrip() {
    final trip = _trip;
    if (trip == null) throw const NotFoundFailure('No active trip.');
    return trip;
  }

  Future<T> _step<T>(Future<T> Function(DeliveryTrip trip) action) async {
    final trip = _requireTrip();
    if (_busy) throw const NotAllowedFailure('Please wait a moment.');
    _busy = true;
    _notify();
    try {
      return await action(trip);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _advance(OrderStatus next, {GeoPoint? position}) =>
      _step((trip) async {
        _trip = await _repository.advance(trip.id, next, position: position);
      });

  /// Needs the rider within [DeliveryTrip.pickupGeofenceM] of the store.
  Future<void> arrivedAtStore() =>
      _advance(OrderStatus.arrivedAtStore, position: _position());

  /// Needs every item checked and the order ready.
  Future<void> pickedUp() => _advance(OrderStatus.pickedUp);

  /// Needs the rider within [DeliveryTask.customerGeofenceM] of the drop.
  Future<void> arrivedAtCustomer() =>
      _advance(OrderStatus.arrivedAtCustomer, position: _position());

  /// Logged on the order whether or not the customer answers.
  Future<({bool answered, Duration duration})> callCustomer() async {
    final trip = _requireTrip();
    final result = await _repository.callCustomer(trip.id);
    await _reload();
    return result;
  }

  Future<void> sendChat(String text) =>
      _local((t) => _repository.sendChat(t.id, text));

  Future<void> requestCustomerLocation() => _step((trip) async {
    _trip = await _repository.requestCustomerLocation(trip.id);
  });

  /// Returns the support ticket reference.
  Future<String> contactSupportAboutAddress() => _step((trip) async {
    final ticket = await _repository.contactSupportAboutAddress(trip.id);
    await _reload();
    return ticket;
  });

  Future<void> markUndeliverable({
    required String reason,
    bool refused = false,
  }) => _step((trip) async {
    _trip = await _repository.markUndeliverable(
      trip.id,
      reason: reason,
      refused: refused,
    );
    _track(_trip);
  });

  /// Needs the rider within [DeliveryTrip.pickupGeofenceM] of the store.
  Future<void> returnedToStore() => _step((trip) async {
    final result = await _repository.returnedToStore(
      trip.id,
      position: _position(),
    );
    _trip = result.trip;
    _track(result.trip, result.returned);
  });

  /// Ends the trip when the notice was the last thing left.
  Future<void> dismissNotice() async {
    final trip = _requireTrip();
    _trip = await _repository.dismissNotice(trip.id);
    _notify();
  }

  Future<void> _local(
    Future<DeliveryTrip> Function(DeliveryTrip trip) change,
  ) async {
    final trip = _requireTrip();
    _trip = await change(trip);
    _notify();
  }

  Future<void> setItemChecked(ItemRef item, {required bool checked}) =>
      _local((t) => _repository.setItemChecked(t.id, item, checked: checked));

  Future<void> checkAllItems() =>
      _local((t) => _repository.checkAllItems(t.id));

  Future<void> setHandlingChecked(OfferTag tag, {required bool checked}) =>
      _local(
        (t) => _repository.setHandlingChecked(t.id, tag, checked: checked),
      );

  Future<void> setBag({required bool sealed, MediaRef? photo}) =>
      _local((t) => _repository.setBag(t.id, sealed: sealed, photo: photo));

  /// "Store closed" is sent with the rider's position for the geofence.
  Future<StoreIssueResult> reportStoreIssue(StoreIssueRequest request) =>
      _step((trip) async {
        final result = await _repository.reportStoreIssue(
          trip.id,
          StoreIssueRequest(
            type: request.type,
            items: request.items,
            resolution: request.resolution,
            note: request.note,
            position: request.position ?? _position(),
          ),
        );
        _trip = result.trip;
        return result;
      });

  Future<void> cancelAfterLongWait() => _step((trip) async {
    _trip = await _repository.cancelAfterLongWait(trip.id);
  });

  /// Acknowledges a cancelled trip; compensation is credited and the rider
  /// is free for new offers.
  Future<TripCancellation> closeCancelledTrip() => _step((trip) async {
    final cancellation = await _repository.closeCancelledTrip(trip.id);
    _trip = null;
    return cancellation;
  });

  /// Completes the current drop and returns it with its final payout. The
  /// trip moves to the next drop, or ends after the last one.
  Future<OtpCheck> verifyDeliveryOtp(String code) async {
    final trip = _requireTrip();
    final result = await _repository.verifyDeliveryOtp(trip.id, code);
    await _reload();
    return result;
  }

  /// False when the simulated payment failed.
  Future<bool> collectUpi(int amountPaise) async {
    final trip = _requireTrip();
    final paid = await _repository.collectUpi(trip.id, amountPaise);
    await _reload();
    return paid;
  }

  Future<DeliveryTask> completeDelivery(DeliveryProof proof) =>
      _step((trip) async {
        final result = await _repository.completeDelivery(trip.id, proof);
        _trip = result.trip;
        _track(result.trip, [result.delivered]);
        return result.delivered;
      });

  void reset() {
    _trip = null;
    _busy = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
