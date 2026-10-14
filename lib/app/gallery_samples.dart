import 'dart:math';

import '../data/demo/demo_order_factory.dart';
import '../data/demo/demo_seed.dart';
import '../models/geo_point.dart';
import '../models/money.dart';
import '../models/order.dart';
import '../models/trip.dart';

/// Static sample models for the component gallery, taken from the demo
/// seed so the gallery never touches live demo state.
class GallerySamples {
  const GallerySamples({
    required this.now,
    required this.rider,
    required this.offer,
    required this.batchedOffer,
    required this.orders,
    required this.incentives,
  });

  factory GallerySamples.fromSeed(DateTime now) {
    final db = DemoSeed.build(now: now);
    final factory = DemoOrderFactory(Random(DemoSeed.defaultSeed));
    final task = factory.buildTask(
      number: 9001,
      store: db.stores.first,
      customer: db.customers.first,
      createdAt: now,
      distanceToPickupM: 1200,
    );
    final rider = db.zones.first.center;
    final offer = factory.buildOffer(
      id: 'sample-offer',
      tasks: [task],
      riderPosition: rider,
      createdAt: now,
    );
    final second = db.customers[1];
    final legM = task.customer.location.distanceMetersTo(second.location);
    final batchedOffer = factory.buildOffer(
      id: 'sample-batch',
      tasks: [
        task,
        factory.buildTask(
          number: 9002,
          store: db.stores.first,
          customer: second,
          createdAt: now,
          distanceToPickupM: 1200,
          batched: true,
          payDistanceM: legM,
          payment: PaymentMode.cod,
        ),
      ],
      riderPosition: rider,
      createdAt: now,
    );

    DeliveryTask? firstWith(OrderStatus status) =>
        db.history.where((o) => o.status == status).firstOrNull;

    return GallerySamples(
      now: now,
      rider: rider,
      offer: offer,
      batchedOffer: batchedOffer,
      orders: [
        ?firstWith(OrderStatus.delivered),
        ?firstWith(OrderStatus.cancelled),
        ?firstWith(OrderStatus.returned),
      ],
      incentives: List.unmodifiable(db.incentives),
    );
  }

  final DateTime now;
  final GeoPoint rider;
  final DeliveryOffer offer;

  /// Two drops, cash on delivery for the second.
  final DeliveryOffer batchedOffer;

  /// One delivered, one cancelled and one returned order.
  final List<DeliveryTask> orders;
  final List<Incentive> incentives;
}
