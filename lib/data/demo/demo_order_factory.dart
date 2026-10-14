import 'dart:math';

import '../../models/geo_point.dart';
import '../../models/order.dart';
import '../../models/trip.dart';
import 'demo_catalog.dart';

/// Builds realistic orders and offers from the catalogue, deterministically
/// for a given [Random].
class DemoOrderFactory {
  DemoOrderFactory(this._random);

  final Random _random;

  static const int basePaise = 2500;
  static const int perKmPaise = 600;
  static const int freeDistanceM = 2000;
  static const int batchBonusPaise = 1000;
  static const int highValuePaise = 200000;

  /// Average two-wheeler speed in city traffic.
  static const double averageSpeedKmh = 18;

  /// Offer payout formula from plan 3.8.6. Distance pay is computed in paise
  /// and rounded to the nearest rupee.
  static PayoutBreakdown payoutFor({
    required int tripDistanceM,
    double surgeMultiplier = 1,
    bool batched = false,
  }) {
    final extraM = max(0, tripDistanceM - freeDistanceM);
    final distancePaise = _roundToRupee(extraM * perKmPaise / 1000);
    final surgePaise = _roundToRupee(basePaise * (surgeMultiplier - 1));
    return PayoutBreakdown(
      basePaise: basePaise,
      distancePaise: distancePaise,
      surgePaise: surgePaise,
      batchBonusPaise: batched ? batchBonusPaise : 0,
    );
  }

  static int _roundToRupee(num paise) => (paise / 100).round() * 100;

  static int minutesFor(int distanceM) =>
      max(1, (distanceM / 1000 / averageSpeedKmh * 60).ceil());

  T pick<T>(List<T> items) => items[_random.nextInt(items.length)];

  CustomerInfo buildCustomer(int index, String zoneId, GeoPoint center) {
    final localities = demoLocalities[zoneId]!;
    final locality = localities[index % localities.length];
    final house = 1 + _random.nextInt(220);
    final flat = _random.nextBool();
    final preferences = <CustomerPreference>{
      if (_random.nextInt(6) == 0) CustomerPreference.leaveAtDoor,
      if (_random.nextInt(8) == 0) CustomerPreference.doNotRing,
    };
    return CustomerInfo(
      id: 'cu-${index + 1}',
      firstName: demoFirstNames[index % demoFirstNames.length],
      lastName: demoLastNames[(index * 7) % demoLastNames.length],
      maskedPhone: '+91 98XXX XX${(index + 1).toString().padLeft(3, '0')}',
      addressLine: flat
          ? 'Flat ${100 + _random.nextInt(800)}, Block ${String.fromCharCode(65 + _random.nextInt(6))}'
          : 'House $house',
      locality: locality,
      floor: flat ? '${1 + _random.nextInt(9)} floor' : 'Ground floor',
      landmark: pick([
        'Near the park',
        'Opposite the temple',
        'Behind the metro station',
        'Next to the bank',
        '',
      ]),
      location: center.offset(
        (_random.nextDouble() - 0.5) * 0.024,
        (_random.nextDouble() - 0.5) * 0.024,
      ),
      instructions: pick(demoInstructions),
      preferences: preferences,
    );
  }

  /// Heavy items are left out when [allowHeavy] is false (cycles, plan
  /// 3.8.7).
  List<OrderItem> buildItems(StoreInfo store, {bool allowHeavy = true}) {
    final pharmacyStore = store.id.endsWith('-rx');
    final pool = demoCatalog
        .where((item) => pharmacyStore ? item.isPharmacy : !item.isPharmacy)
        .where((item) => allowHeavy || item.tag != OfferTag.heavy)
        .toList();
    final count = 2 + _random.nextInt(4);
    final chosen = <CatalogItem>{};
    while (chosen.length < count) {
      chosen.add(pick(pool));
    }
    return chosen
        .map(
          (item) => OrderItem(
            name: item.name,
            unit: item.unit,
            quantity: item.priceRupees > 250 ? 1 : 1 + _random.nextInt(2),
            unitPricePaise: item.priceRupees * 100,
          ),
        )
        .toList();
  }

  /// Four digits the store matches against its copy of the order. Derived
  /// from [tripId] so it doesn't disturb the offer sequence.
  static String pickupCode(String tripId) {
    var hash = 0x811c9dc5;
    for (final unit in tripId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return (1000 + hash % 9000).toString();
  }

  Set<OfferTag> tagsFor(List<OrderItem> items) {
    final names = items.map((i) => i.name).toSet();
    return demoCatalog
        .where((c) => c.tag != null && names.contains(c.name))
        .map((c) => c.tag!)
        .toSet();
  }

  /// A new order in `offered` state.
  ///
  /// [payDistanceM] is the distance this order pays for (by default rider →
  /// store → customer); the second order of a batch pays only for the leg
  /// between drops and carries the batch bonus. [routeDistanceM] is the
  /// whole route to this customer, used for the promised time.
  DeliveryTask buildTask({
    required int number,
    required StoreInfo store,
    required CustomerInfo customer,
    required DateTime createdAt,
    required int distanceToPickupM,
    double surgeMultiplier = 1,
    bool batched = false,
    int? payDistanceM,
    int? routeDistanceM,
    PaymentMode? payment,
    bool allowHeavy = true,
  }) {
    final items = buildItems(store, allowHeavy: allowHeavy);
    final tags = tagsFor(items);
    final valuePaise = items.fold(0, (sum, item) => sum + item.linePaise);
    final randomCod = _random.nextInt(100) < 35;
    final isCod = payment == null ? randomCod : payment == PaymentMode.cod;
    final distanceM = store.location.distanceMetersTo(customer.location);
    final requiredProof = valuePaise > highValuePaise
        ? ProofMethod.otpAndPhoto
        : !isCod &&
              customer.preferences.contains(CustomerPreference.leaveAtDoor)
        ? ProofMethod.photo
        : ProofMethod.otp;

    return DeliveryTask(
      orderId: 'ord-$number',
      displayId: '#QW$number',
      store: store,
      customer: customer,
      items: items,
      payment: PaymentInfo(
        mode: isCod ? PaymentMode.cod : PaymentMode.prepaid,
        orderValuePaise: valuePaise,
        amountToCollectPaise: isCod ? valuePaise : 0,
      ),
      requiredProof: requiredProof,
      deliveryOtp: (1000 + _random.nextInt(9000)).toString(),
      isReturnable:
          !tags.contains(OfferTag.coldChain) &&
          !tags.contains(OfferTag.pharmacy),
      promisedBy: createdAt.add(
        Duration(
          minutes:
              minutesFor(routeDistanceM ?? distanceToPickupM + distanceM) + 12,
        ),
      ),
      payout: payoutFor(
        tripDistanceM: payDistanceM ?? distanceToPickupM + distanceM,
        surgeMultiplier: surgeMultiplier,
        batched: batched,
      ),
      distanceM: distanceM,
      timeline: [OrderEvent(type: OrderEventType.offered, at: createdAt)],
    );
  }

  /// An offer for one order, or two orders from the same store in drop
  /// order. Pay is the sum of the orders' pay.
  DeliveryOffer buildOffer({
    required String id,
    required List<DeliveryTask> tasks,
    required GeoPoint riderPosition,
    required DateTime createdAt,
    int timeoutSeconds = 30,
  }) {
    final store = tasks.first.store;
    final distanceToPickupM = riderPosition.distanceMetersTo(store.location);
    var tripDistanceM = distanceToPickupM;
    var from = store.location;
    for (final task in tasks) {
      tripDistanceM += from.distanceMetersTo(task.customer.location);
      from = task.customer.location;
    }
    final items = [for (final task in tasks) ...task.items];
    final tags = tagsFor(items);
    final itemCount = items.fold(0, (sum, i) => sum + i.quantity);
    return DeliveryOffer(
      id: id,
      orders: tasks,
      pickup: Stop(
        name: store.name,
        address: store.address,
        location: store.location,
      ),
      drops: [
        for (final task in tasks)
          Stop(
            name: task.customer.firstName,
            address: task.customer.locality,
            location: task.customer.location,
          ),
      ],
      distanceToPickupM: distanceToPickupM,
      tripDistanceM: tripDistanceM,
      estimatedMinutes: minutesFor(tripDistanceM) + 4 * tasks.length,
      payout: tasks.map((t) => t.payout).reduce((a, b) => a + b),
      createdAt: createdAt,
      timeoutSeconds: timeoutSeconds,
      tags: tags,
      bagSize: tags.contains(OfferTag.heavy) || itemCount > 6
          ? BagSize.large
          : itemCount > 3
          ? BagSize.medium
          : BagSize.small,
    );
  }
}
