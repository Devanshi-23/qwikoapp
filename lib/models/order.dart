import '../core/formatters.dart';
import 'geo_point.dart';
import 'media_ref.dart';

class StoreInfo {
  const StoreInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.maskedPhone,
    required this.pickupInstructions,
    required this.counterLabel,
    required this.zoneId,
  });

  final String id;
  final String name;
  final String address;
  final GeoPoint location;
  final String maskedPhone;
  final String pickupInstructions;
  final String counterLabel;
  final String zoneId;

  @override
  bool operator ==(Object other) => other is StoreInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'StoreInfo($id, $name)';
}

enum CustomerPreference { leaveAtDoor, doNotRing, contactless }

class CustomerInfo {
  const CustomerInfo({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.maskedPhone,
    required this.addressLine,
    required this.locality,
    required this.location,
    this.floor = '',
    this.landmark = '',
    this.instructions = '',
    this.preferences = const {},
  });

  final String id;
  final String firstName;
  final String lastName;
  final String maskedPhone;
  final String addressLine;
  final String locality;
  final GeoPoint location;
  final String floor;
  final String landmark;
  final String instructions;
  final Set<CustomerPreference> preferences;

  String get fullName => '$firstName $lastName';

  String get fullAddress => '$addressLine, $locality';

  CustomerInfo copyWith({GeoPoint? location}) => CustomerInfo(
    id: id,
    firstName: firstName,
    lastName: lastName,
    maskedPhone: maskedPhone,
    addressLine: addressLine,
    locality: locality,
    location: location ?? this.location,
    floor: floor,
    landmark: landmark,
    instructions: instructions,
    preferences: preferences,
  );

  @override
  bool operator ==(Object other) => other is CustomerInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CustomerInfo($id, $fullName)';
}

enum ItemStatus { normal, missing, damaged, replaced, removed }

class OrderItem {
  const OrderItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.unitPricePaise,
    this.isPicked = false,
    this.status = ItemStatus.normal,
  });

  final String name;
  final int quantity;

  /// Pack size shown to the rider, e.g. `1L` or `500g`.
  final String unit;
  final int unitPricePaise;
  final bool isPicked;
  final ItemStatus status;

  int get linePaise =>
      status == ItemStatus.removed ? 0 : unitPricePaise * quantity;

  String get label =>
      unit.isEmpty ? '$name x $quantity' : '$name $unit x $quantity';

  OrderItem copyWith({bool? isPicked, ItemStatus? status}) => OrderItem(
    name: name,
    quantity: quantity,
    unit: unit,
    unitPricePaise: unitPricePaise,
    isPicked: isPicked ?? this.isPicked,
    status: status ?? this.status,
  );

  @override
  bool operator ==(Object other) =>
      other is OrderItem &&
      other.name == name &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.unitPricePaise == unitPricePaise &&
      other.isPicked == isPicked &&
      other.status == status;

  @override
  int get hashCode =>
      Object.hash(name, quantity, unit, unitPricePaise, isPicked, status);
}

enum PaymentMode { prepaid, cod }

class PaymentInfo {
  const PaymentInfo({
    required this.mode,
    required this.orderValuePaise,
    required this.amountToCollectPaise,
  });

  final PaymentMode mode;

  /// Basket value including fees; decides the high-value proof rule.
  final int orderValuePaise;

  /// Zero for prepaid orders.
  final int amountToCollectPaise;

  bool get isCod => mode == PaymentMode.cod;

  @override
  bool operator ==(Object other) =>
      other is PaymentInfo &&
      other.mode == mode &&
      other.orderValuePaise == orderValuePaise &&
      other.amountToCollectPaise == amountToCollectPaise;

  @override
  int get hashCode => Object.hash(mode, orderValuePaise, amountToCollectPaise);
}

enum ProofMethod { otp, photo, otpAndPhoto }

enum CollectionMethod { cash, upiQr, split }

class DeliveryProof {
  const DeliveryProof({
    required this.method,
    required this.capturedAt,
    this.otpVerified = false,
    this.photo,
    this.cashCollectedPaise = 0,
    this.changeGivenPaise = 0,
    this.upiCollectedPaise = 0,
    this.collectedVia,
  });

  final ProofMethod method;
  final DateTime capturedAt;
  final bool otpVerified;
  final MediaRef? photo;
  final int cashCollectedPaise;
  final int changeGivenPaise;
  final int upiCollectedPaise;
  final CollectionMethod? collectedVia;
}

enum OrderEventType {
  offered,
  accepted,
  arrivedAtStore,
  pickedUp,
  arrivedAtCustomer,
  delivered,
  cancelled,
  returningToStore,
  returned,
  issueReported,
  callAttempted,
  chatSent,
  chatReceived,
  locationShared,
  proofCaptured,
  paymentCollected,
  tipReceived,
  ratingReceived,
}

class OrderEvent {
  const OrderEvent({
    required this.type,
    required this.at,
    this.note,
    this.queued = false,
  });

  final OrderEventType type;
  final DateTime at;
  final String? note;

  /// True while recorded offline and not yet synced.
  final bool queued;

  OrderEvent synced() => OrderEvent(type: type, at: at, note: note);

  @override
  String toString() => 'OrderEvent(${type.name} at $at)';
}

/// States from Appendix A of the plan.
enum OrderStatus {
  offered,
  accepted,
  headingToStore,
  arrivedAtStore,
  pickedUp,
  headingToCustomer,
  arrivedAtCustomer,
  delivered,
  returningToStore,
  returned,
  disposed,
  reassigned,
  handedOver,
  cancelled,
  declined,
  missed,
  unavailable;

  bool get isFinal => const {
    delivered,
    returned,
    disposed,
    reassigned,
    handedOver,
    cancelled,
    declined,
    missed,
    unavailable,
  }.contains(this);

  String get label => switch (this) {
    delivered => 'Delivered',
    cancelled => 'Cancelled',
    returned => 'Returned',
    disposed => 'Disposed',
    reassigned => 'Reassigned',
    handedOver => 'Handed over',
    _ => 'In progress',
  };
}

enum IssueType {
  orderNotReady,
  itemMissing,
  itemDamaged,
  storeClosed,
  wrongOrder,
  addressNotFound,
  customerUnreachable,
  customerRefused,
  vehicleBreakdown,
  payMissing,
  wrongDistance,
  tipMissing,
  other,
}

enum IssueOutcome {
  waiting,
  continued,
  replaced,
  removed,
  cancelled,
  escalated,
}

class IssueReport {
  const IssueReport({
    required this.id,
    required this.type,
    required this.at,
    this.affectedItems = const [],
    this.note,
    this.media,
    this.outcome,
    this.ticketId,
  });

  final String id;
  final IssueType type;
  final DateTime at;
  final List<String> affectedItems;
  final String? note;
  final MediaRef? media;
  final IssueOutcome? outcome;
  final String? ticketId;
}

class PayoutBreakdown {
  const PayoutBreakdown({
    this.basePaise = 0,
    this.distancePaise = 0,
    this.surgePaise = 0,
    this.waitingPaise = 0,
    this.batchBonusPaise = 0,
    this.compensationPaise = 0,
    this.tipPaise = 0,
  });

  final int basePaise;
  final int distancePaise;
  final int surgePaise;
  final int waitingPaise;
  final int batchBonusPaise;
  final int compensationPaise;
  final int tipPaise;

  /// Delivery fee: base + distance.
  int get orderPayPaise => basePaise + distancePaise;

  int get totalPaise =>
      basePaise +
      distancePaise +
      surgePaise +
      waitingPaise +
      batchBonusPaise +
      compensationPaise +
      tipPaise;

  PayoutBreakdown copyWith({
    int? waitingPaise,
    int? batchBonusPaise,
    int? compensationPaise,
    int? tipPaise,
  }) => PayoutBreakdown(
    basePaise: basePaise,
    distancePaise: distancePaise,
    surgePaise: surgePaise,
    waitingPaise: waitingPaise ?? this.waitingPaise,
    batchBonusPaise: batchBonusPaise ?? this.batchBonusPaise,
    compensationPaise: compensationPaise ?? this.compensationPaise,
    tipPaise: tipPaise ?? this.tipPaise,
  );

  /// Combined pay, for example both orders of a batched offer.
  PayoutBreakdown operator +(PayoutBreakdown other) => PayoutBreakdown(
    basePaise: basePaise + other.basePaise,
    distancePaise: distancePaise + other.distancePaise,
    surgePaise: surgePaise + other.surgePaise,
    waitingPaise: waitingPaise + other.waitingPaise,
    batchBonusPaise: batchBonusPaise + other.batchBonusPaise,
    compensationPaise: compensationPaise + other.compensationPaise,
    tipPaise: tipPaise + other.tipPaise,
  );

  @override
  bool operator ==(Object other) =>
      other is PayoutBreakdown &&
      other.basePaise == basePaise &&
      other.distancePaise == distancePaise &&
      other.surgePaise == surgePaise &&
      other.waitingPaise == waitingPaise &&
      other.batchBonusPaise == batchBonusPaise &&
      other.compensationPaise == compensationPaise &&
      other.tipPaise == tipPaise;

  @override
  int get hashCode => Object.hash(
    basePaise,
    distancePaise,
    surgePaise,
    waitingPaise,
    batchBonusPaise,
    compensationPaise,
    tipPaise,
  );

  @override
  String toString() => 'PayoutBreakdown(total: $totalPaise paise)';
}

class DeliveryTask {
  const DeliveryTask({
    required this.orderId,
    required this.displayId,
    required this.store,
    required this.customer,
    required this.items,
    required this.payment,
    required this.requiredProof,
    required this.deliveryOtp,
    required this.payout,
    required this.distanceM,
    required this.promisedBy,
    this.tripId,
    this.isReturnable = true,
    this.status = OrderStatus.offered,
    this.timeline = const [],
    this.proof,
    this.issues = const [],
    this.contactAttempts = 0,
  });

  final String orderId;

  /// Short id shown to riders and store staff, e.g. `#QW1031`.
  final String displayId;
  final String? tripId;
  final StoreInfo store;
  final CustomerInfo customer;
  final List<OrderItem> items;
  final PaymentInfo payment;
  final ProofMethod requiredProof;
  final String deliveryOtp;
  final bool isReturnable;

  /// Promised delivery time; used for the on-time rate.
  final DateTime promisedBy;
  final OrderStatus status;
  final List<OrderEvent> timeline;
  final DeliveryProof? proof;
  final List<IssueReport> issues;
  final PayoutBreakdown payout;

  /// Store to customer distance.
  final int distanceM;
  final int contactAttempts;

  /// "I've arrived" at the customer is allowed within this distance.
  static const int customerGeofenceM = 100;

  /// "Mark undeliverable" needs this many calls and this long at the door
  /// (unless the customer refuses the order).
  static const int requiredCallAttempts = 2;
  static const Duration doorWait = Duration(minutes: 5);

  int get callAttempts =>
      timeline.where((e) => e.type == OrderEventType.callAttempted).length;

  DateTime? get arrivedAtCustomerAt => timeOf(OrderEventType.arrivedAtCustomer);

  Duration waitedAtDoor(DateTime now) {
    final arrived = arrivedAtCustomerAt;
    if (arrived == null || now.isBefore(arrived)) return Duration.zero;
    return now.difference(arrived);
  }

  /// Why "Mark undeliverable" is disabled, or null when it is allowed.
  String? undeliverableBlockedReason(DateTime now) {
    if (status != OrderStatus.arrivedAtCustomer) {
      return "Available after you tap \"I've arrived\".";
    }
    final calls = requiredCallAttempts - callAttempts;
    final wait = doorWait - waitedAtDoor(now);
    final parts = [
      if (calls > 0)
        'call the customer $calls more ${calls == 1 ? 'time' : 'times'}',
      if (wait > Duration.zero) 'wait ${formatClock(wait)} more',
    ];
    if (parts.isEmpty) return null;
    final text = parts.join(' and ');
    return '${text[0].toUpperCase()}${text.substring(1)}.';
  }

  /// Pay for an order that wasn't delivered after pickup (plan 3.8.3): half
  /// the order pay, plus the distance pay when it is brought back.
  PayoutBreakdown failedPayout({required bool returned, int waitingPaise = 0}) {
    final half = ((payout.orderPayPaise * 0.5) / 100).round() * 100;
    return PayoutBreakdown(
      compensationPaise: half + (returned ? payout.distancePaise : 0),
      waitingPaise: waitingPaise,
    );
  }

  /// Chat messages: sent by the rider and received from the customer.
  Iterable<OrderEvent> get chat => timeline.where(
    (e) =>
        e.type == OrderEventType.chatSent ||
        e.type == OrderEventType.chatReceived,
  );

  /// Time of the most recent event (falls back to the promised time).
  DateTime get lastUpdatedAt =>
      timeline.isEmpty ? promisedBy : timeline.last.at;

  /// When the order reached its end state; history is dated by this, so a
  /// later tip doesn't move it.
  DateTime get endedAt =>
      timeOf(OrderEventType.delivered) ??
      timeOf(OrderEventType.returned) ??
      timeOf(OrderEventType.cancelled) ??
      lastUpdatedAt;

  DateTime? timeOf(OrderEventType type) {
    for (final event in timeline.reversed) {
      if (event.type == type) return event.at;
    }
    return null;
  }

  /// Earnings credited for this order (zero until it reaches an end state
  /// that pays).
  int get earnedPaise => switch (status) {
    OrderStatus.delivered ||
    OrderStatus.returned ||
    OrderStatus.disposed ||
    OrderStatus.handedOver ||
    OrderStatus.cancelled => payout.totalPaise,
    _ => 0,
  };

  DeliveryTask copyWith({
    String? tripId,
    CustomerInfo? customer,
    OrderStatus? status,
    List<OrderEvent>? timeline,
    DeliveryProof? proof,
    List<IssueReport>? issues,
    PayoutBreakdown? payout,
    List<OrderItem>? items,
    PaymentInfo? payment,
    int? contactAttempts,
  }) => DeliveryTask(
    orderId: orderId,
    displayId: displayId,
    tripId: tripId ?? this.tripId,
    store: store,
    customer: customer ?? this.customer,
    items: items ?? this.items,
    payment: payment ?? this.payment,
    requiredProof: requiredProof,
    deliveryOtp: deliveryOtp,
    isReturnable: isReturnable,
    promisedBy: promisedBy,
    status: status ?? this.status,
    timeline: timeline ?? this.timeline,
    proof: proof ?? this.proof,
    issues: issues ?? this.issues,
    payout: payout ?? this.payout,
    distanceM: distanceM,
    contactAttempts: contactAttempts ?? this.contactAttempts,
  );

  /// Moves to [next] and records the matching timeline event.
  DeliveryTask transition(
    OrderStatus next,
    DateTime at, {
    OrderEventType? event,
    String? note,
    bool queued = false,
  }) => copyWith(
    status: next,
    timeline: event == null
        ? timeline
        : [
            ...timeline,
            OrderEvent(type: event, at: at, note: note, queued: queued),
          ],
  );

  /// Adds a timeline event without changing the status.
  DeliveryTask record(
    OrderEventType event,
    DateTime at, {
    String? note,
    bool queued = false,
  }) => transition(status, at, event: event, note: note, queued: queued);

  /// Order value and cash to collect after items were removed. Rider pay
  /// is unchanged (plan 3.8.4).
  PaymentInfo get recomputedPayment {
    final value = items.fold(0, (sum, item) => sum + item.linePaise);
    return PaymentInfo(
      mode: payment.mode,
      orderValuePaise: value,
      amountToCollectPaise: payment.isCod ? value : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeliveryTask &&
      other.orderId == orderId &&
      other.status == status &&
      other.timeline.length == timeline.length &&
      _queuedCount(other.timeline) == _queuedCount(timeline) &&
      other.issues.length == issues.length &&
      other.payout == payout &&
      other.payment == payment &&
      _sameItems(other.items, items);

  @override
  int get hashCode => Object.hash(
    orderId,
    status,
    timeline.length,
    payout,
    payment,
    Object.hashAll(items),
  );

  @override
  String toString() => 'DeliveryTask($displayId, ${status.name})';
}

int _queuedCount(List<OrderEvent> timeline) =>
    timeline.where((event) => event.queued).length;

bool _sameItems(List<OrderItem> a, List<OrderItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
