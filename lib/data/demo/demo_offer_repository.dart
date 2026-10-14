import 'dart:async';

import '../../core/domain_events.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/activity.dart';
import '../../models/geo_point.dart';
import '../../models/order.dart';
import '../../models/partner.dart';
import '../../models/trip.dart';
import '../repositories/demo_controls.dart';
import '../repositories/offer_repository.dart';
import 'demo_backend.dart';
import 'demo_order_factory.dart';

class DemoOfferRepository implements OfferRepository {
  DemoOfferRepository(this._backend);

  final DemoBackend _backend;

  @override
  Stream<OfferEvent> watchOffers({required GeoPoint Function() position}) {
    late final StreamController<OfferEvent> controller;
    Timer? schedule;
    StreamSubscription<OfferRequest>? requests;
    final withdrawals = <Timer>[];

    void push(OfferRequest request) {
      if (!_backend.engine.networkAvailable || _backend.db.activeTrip != null) {
        return;
      }
      final offer = _generate(position(), request);
      controller.add(OfferArrived(offer));
      if (!_backend.takeNextOffer) return;
      _backend.takeNextOffer = false;
      _backend.db.takenOfferIds.add(offer.id);
      withdrawals.add(
        Timer(_backend.offerTakenAfter, () {
          _recordTaken(offer);
          controller.add(OfferWithdrawn(offer.id));
        }),
      );
    }

    void scheduleNext(Duration delay) {
      schedule = Timer(delay, () {
        push(const OfferRequest());
        scheduleNext(_backend.offerInterval);
      });
    }

    controller = StreamController<OfferEvent>(
      onListen: () {
        scheduleNext(_backend.firstOfferDelay);
        requests = _backend.offerRequests.listen(push);
      },
      onCancel: () {
        schedule?.cancel();
        requests?.cancel();
        for (final timer in withdrawals) {
          timer.cancel();
        }
      },
    );
    return controller.stream;
  }

  final Set<String> _recordedTaken = {};

  void _recordTaken(DeliveryOffer offer) {
    if (!_recordedTaken.add(offer.id)) return;
    _backend.recordActivity(ActivityType.offerWithdrawn, offer.displayIds);
  }

  DeliveryOffer _generate(GeoPoint position, OfferRequest request) {
    final db = _backend.db;
    final factory = _backend.factory;
    final now = _backend.clock.now();
    final riderZone = _backend.zoneNearest(position).id;
    final nearby = db.stores.where((s) => s.zoneId == riderZone).toList();
    final store = factory.pick(nearby.isEmpty ? db.stores : nearby);
    final customers = db.customers
        .where((c) => c.location.distanceMetersTo(store.location) < 3500)
        .toList();
    final pool = customers.isEmpty ? db.customers : customers;
    final first = factory.pick(pool);
    final zones = _backend.zonesAt(now);
    final zone = zones.firstWhere(
      (z) => z.id == store.zoneId,
      orElse: () => zones.first,
    );
    final allowHeavy = db.partner.vehicle?.type != VehicleType.cycle;
    final toStoreM = position.distanceMetersTo(store.location);

    final tasks = [
      factory.buildTask(
        number: db.nextOrderNumber++,
        store: store,
        customer: first,
        createdAt: now,
        distanceToPickupM: toStoreM,
        surgeMultiplier: zone.surgeMultiplier,
        payment: request.payment,
        allowHeavy: allowHeavy,
      ),
    ];
    if (request.batched) {
      final others = pool.where((c) => c.id != first.id).toList()
        ..sort(
          (a, b) => a.location
              .distanceMetersTo(first.location)
              .compareTo(b.location.distanceMetersTo(first.location)),
        );
      final second = others.isEmpty
          ? first
          : factory.pick(others.take(4).toList());
      final legM = first.location.distanceMetersTo(second.location);
      tasks.add(
        factory.buildTask(
          number: db.nextOrderNumber++,
          store: store,
          customer: second,
          createdAt: now,
          distanceToPickupM: toStoreM,
          surgeMultiplier: zone.surgeMultiplier,
          batched: true,
          payDistanceM: legM,
          routeDistanceM: toStoreM + tasks.first.distanceM + legM,
          payment: request.payment,
          allowHeavy: allowHeavy,
        ),
      );
    }
    return factory.buildOffer(
      id: _backend.ids.next('off'),
      tasks: tasks,
      riderPosition: position,
      createdAt: now,
      timeoutSeconds: request.timeoutSeconds,
    );
  }

  @override
  Future<DeliveryTrip> accept(
    DeliveryOffer offer, {
    required GeoPoint position,
  }) => _backend.engine.run(OperationType.acceptOffer, () {
    final db = _backend.db;
    if (db.activeTrip != null) {
      throw const NotAllowedFailure('Finish your current trip first.');
    }
    if (db.takenOfferIds.contains(offer.id)) {
      _recordTaken(offer);
      throw const OfferUnavailableFailure();
    }
    if (!db.cash.canCollect(offer.codAmountPaise)) {
      throw NotAllowedFailure(codLimitReason(db.cash.roomPaise));
    }
    final now = _backend.clock.now();
    final tripId = _backend.ids.next('trip');
    final tasks = offer.orders
        .map(
          (task) => task
              .copyWith(tripId: tripId)
              .transition(
                OrderStatus.accepted,
                now,
                event: OrderEventType.accepted,
              )
              .transition(OrderStatus.headingToStore, now),
        )
        .toList();
    final trip = DeliveryTrip(
      id: tripId,
      offerId: offer.id,
      store: tasks.first.store,
      tasks: tasks,
      acceptedAt: now,
      startPosition: position,
      pickupCode: DemoOrderFactory.pickupCode(tripId),
      tags: offer.tags,
      routeSnapshot: [
        position,
        offer.pickup.location,
        ...offer.drops.map((d) => d.location),
      ],
    );
    db.activeTrip = trip;
    _backend.recordActivity(ActivityType.offerAccepted, offer.displayIds);
    _backend.events.emit(const TripChanged());
    return trip;
  });

  @override
  Future<void> decline(
    DeliveryOffer offer,
    DeclineReason reason, {
    String? note,
  }) => _backend.engine.run(OperationType.declineOffer, () {
    final trimmed = note?.trim() ?? '';
    final details = trimmed.isEmpty
        ? '${offer.displayIds} · ${reason.label}'
        : '${offer.displayIds} · ${reason.label}: $trimmed';
    _backend.recordActivity(ActivityType.offerDeclined, details);
  });

  @override
  Future<void> markMissed(DeliveryOffer offer) =>
      _backend.engine.run(OperationType.declineOffer, () {
        _backend.recordActivity(ActivityType.offerMissed, offer.displayIds);
      });
}
