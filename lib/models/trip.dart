import 'dart:math';

import 'geo_point.dart';
import 'media_ref.dart';
import 'order.dart';

class Stop {
  const Stop({
    required this.name,
    required this.address,
    required this.location,
  });

  final String name;

  /// Full address for pickups; locality only for drops until accepted.
  final String address;
  final GeoPoint location;
}

enum OfferTag {
  heavy('Heavy', 'Heavy items. Lift with care.'),
  fragile('Fragile', 'Fragile items. Keep upright and handle gently.'),
  coldChain('Cold chain', 'Carry a cold bag. Keep frozen items sealed.'),
  pharmacy('Pharmacy', 'Collect the sealed pharmacy bag. Do not open it.');

  const OfferTag(this.label, this.instruction);

  final String label;

  /// Handling note shown on the offer and at pickup.
  final String instruction;

  /// Extra checklist line the rider confirms at pickup (plan 3.8.7).
  String? get pickupCheck => switch (this) {
    coldChain => 'Frozen items packed in a cold bag',
    pharmacy => 'Sealed pharmacy bag collected',
    _ => null,
  };
}

enum BagSize {
  small('Small bag'),
  medium('Medium bag'),
  large('Large bag');

  const BagSize(this.label);

  final String label;
}

enum DeclineReason {
  tooFar('Too far'),
  lowPayout('Low payout'),
  vehicleIssue('Vehicle issue'),
  goingOfflineSoon('Going offline soon'),
  other('Other');

  const DeclineReason(this.label);

  final String label;
}

class DeliveryOffer {
  const DeliveryOffer({
    required this.id,
    required this.orders,
    required this.pickup,
    required this.drops,
    required this.distanceToPickupM,
    required this.tripDistanceM,
    required this.estimatedMinutes,
    required this.payout,
    required this.createdAt,
    this.shownAt,
    this.timeoutSeconds = 30,
    this.tags = const {},
    this.bagSize = BagSize.small,
  });

  final String id;

  /// One order, or two for a batched offer.
  final List<DeliveryTask> orders;
  final Stop pickup;
  final List<Stop> drops;
  final int distanceToPickupM;
  final int tripDistanceM;
  final int estimatedMinutes;
  final PayoutBreakdown payout;
  final DateTime createdAt;

  /// Set when the offer becomes visible; the countdown starts here.
  final DateTime? shownAt;
  final int timeoutSeconds;
  final Set<OfferTag> tags;
  final BagSize bagSize;

  bool get isBatched => orders.length > 1;

  int get itemCount => orders.fold(
    0,
    (sum, o) => sum + o.items.fold(0, (s, i) => s + i.quantity),
  );

  int get codAmountPaise =>
      orders.fold(0, (sum, o) => sum + o.payment.amountToCollectPaise);

  bool get isCod => codAmountPaise > 0;

  DateTime? get expiresAt => shownAt?.add(Duration(seconds: timeoutSeconds));

  /// Order IDs for logs, for example "#QW1031, #QW1032".
  String get displayIds => orders.map((o) => o.displayId).join(', ');

  DeliveryOffer copyWith({DateTime? shownAt, int? timeoutSeconds}) =>
      DeliveryOffer(
        id: id,
        orders: orders,
        pickup: pickup,
        drops: drops,
        distanceToPickupM: distanceToPickupM,
        tripDistanceM: tripDistanceM,
        estimatedMinutes: estimatedMinutes,
        payout: payout,
        createdAt: createdAt,
        shownAt: shownAt ?? this.shownAt,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
        tags: tags,
        bagSize: bagSize,
      );

  @override
  bool operator ==(Object other) =>
      other is DeliveryOffer &&
      other.id == id &&
      other.shownAt == shownAt &&
      other.timeoutSeconds == timeoutSeconds;

  @override
  int get hashCode => Object.hash(id, shownAt, timeoutSeconds);

  @override
  String toString() => 'DeliveryOffer($id, ${payout.totalPaise} paise)';
}

/// What the offer feed pushes while the rider is listening.
sealed class OfferEvent {
  const OfferEvent();
}

class OfferArrived extends OfferEvent {
  const OfferArrived(this.offer);

  final DeliveryOffer offer;
}

/// The offer can no longer be accepted, for example because another
/// partner took it.
class OfferWithdrawn extends OfferEvent {
  const OfferWithdrawn(this.offerId);

  final String offerId;
}

enum TripStatus {
  headingToStore,
  atStore,
  inProgress,
  returningToStore,
  completed,
  cancelled,
}

enum CancelledBy {
  store('Store'),
  customer('Customer'),
  system('Qwiko');

  const CancelledBy(this.label);

  final String label;
}

/// Why a trip ended before pickup and what the rider is paid for it
/// (plan 3.8.3). The trip stays on screen until the rider acknowledges.
class TripCancellation {
  const TripCancellation({
    required this.by,
    required this.reason,
    required this.at,
    required this.atStore,
    this.compensationPaise = 0,
    this.waitingPaise = 0,
  });

  final CancelledBy by;
  final String reason;
  final DateTime at;

  /// True when the rider was already at the store; they confirm leaving.
  final bool atStore;
  final int compensationPaise;
  final int waitingPaise;

  int get totalPaise => compensationPaise + waitingPaise;
}

/// Something that happened to the trip that the rider must read, for
/// example a customer cancelling mid-route. Shown until dismissed.
class TripNotice {
  const TripNotice({required this.title, required this.message});

  final String title;
  final String message;
}

/// One pickup checklist line, addressed by order and item position.
typedef ItemRef = ({String orderId, int index});

const Object _keep = Object();

/// Everything the rider does after accepting one offer: a single pickup and
/// one or two drops (plan 3.8.2).
class DeliveryTrip {
  const DeliveryTrip({
    required this.id,
    required this.offerId,
    required this.store,
    required this.tasks,
    required this.acceptedAt,
    required this.startPosition,
    this.currentTaskIndex = 0,
    this.status = TripStatus.headingToStore,
    this.routeSnapshot = const [],
    this.waitStartedAt,
    this.waitingPaise = 0,
    this.pickupCode = '',
    this.tags = const {},
    this.checkedTags = const {},
    this.bagSealed = false,
    this.bagPhoto,
    this.orderReadyAt,
    this.storeFixingUntil,
    this.cancellation,
    this.notice,
  });

  /// "I've arrived" at the store is allowed within this distance.
  static const int pickupGeofenceM = 200;

  /// Waiting at the store is free for this long, then paid per minute.
  static const Duration freeWait = Duration(minutes: 5);
  static const int waitingPaisePerMinute = 100;

  /// "Cancel and get compensation" unlocks after waiting this long for an
  /// order that is not ready.
  static const Duration longWait = Duration(minutes: 15);

  /// Paid when a trip is cancelled after the rider went to the store.
  static const int storeTripCompensationPaise = 1500;

  /// Heading-to-store cancellations pay only beyond this distance.
  static const int compensationMinTravelM = 500;

  final String id;
  final String offerId;
  final StoreInfo store;

  /// Ordered by drop sequence.
  final List<DeliveryTask> tasks;
  final DateTime acceptedAt;

  /// Rider position when the offer was accepted.
  final GeoPoint startPosition;
  final int currentTaskIndex;
  final TripStatus status;

  /// Full planned route, kept for order history.
  final List<GeoPoint> routeSnapshot;
  final DateTime? waitStartedAt;

  /// Waiting pay, frozen when the order is picked up.
  final int waitingPaise;

  /// Shown to store staff with the order ID at handover.
  final String pickupCode;
  final Set<OfferTag> tags;

  /// Handling checks ([OfferTag.pickupCheck]) the rider has confirmed.
  final Set<OfferTag> checkedTags;
  final bool bagSealed;
  final MediaRef? bagPhoto;

  /// Set when the store said the order is not ready yet.
  final DateTime? orderReadyAt;

  /// Set when the rider reported a wrong order and the store is fixing it.
  final DateTime? storeFixingUntil;
  final TripCancellation? cancellation;
  final TripNotice? notice;

  DeliveryTask get currentTask => tasks[currentTaskIndex];

  /// Orders being taken back to the store.
  List<DeliveryTask> get returnTasks =>
      tasks.where((t) => t.status == OrderStatus.returningToStore).toList();

  bool get isFinished => tasks.every((t) => t.status.isFinal);

  bool get isPickedUp =>
      status != TripStatus.headingToStore &&
      status != TripStatus.atStore &&
      status != TripStatus.cancelled;

  /// True while a step taken offline has not reached the server yet.
  bool get hasQueuedSteps =>
      tasks.any((t) => t.timeline.any((event) => event.queued));

  List<OfferTag> get pickupChecks =>
      tags.where((t) => t.pickupCheck != null).toList();

  /// Items still to hand over, across every order in the trip.
  Iterable<OrderItem> get pickupItems => tasks
      .expand((t) => t.items)
      .where((item) => item.status != ItemStatus.removed);

  /// Checklist lines (items and handling checks) not yet ticked.
  int get uncheckedCount =>
      pickupItems.where((item) => !item.isPicked).length +
      pickupChecks.where((t) => !checkedTags.contains(t)).length;

  bool isOrderReady(DateTime now) =>
      orderReadyAt == null || !now.isBefore(orderReadyAt!);

  bool isStoreFixing(DateTime now) =>
      storeFixingUntil != null && now.isBefore(storeFixingUntil!);

  Duration waitedAt(DateTime now) {
    final start = waitStartedAt;
    if (start == null || now.isBefore(start)) return Duration.zero;
    return now.difference(start);
  }

  /// ₹1 per full minute after the free [freeWait]; frozen after pickup.
  int waitingPaiseAt(DateTime now) {
    if (status != TripStatus.atStore) return waitingPaise;
    final paid = waitedAt(now) - freeWait;
    return max(0, paid.inMinutes) * waitingPaisePerMinute;
  }

  bool isWaitingPaid(DateTime now) =>
      status == TripStatus.atStore && waitedAt(now) >= freeWait;

  /// The store is late and the rider has waited long enough to leave.
  bool canCancelForWaitAt(DateTime now) =>
      status == TripStatus.atStore &&
      !isOrderReady(now) &&
      waitedAt(now) >= longWait;

  /// Why "Picked up" is disabled right now, or null when it is allowed.
  String? pickupBlockedReason(DateTime now) {
    if (status == TripStatus.headingToStore) {
      return 'Mark that you have arrived at the store first.';
    }
    if (status != TripStatus.atStore) return 'This order is not at pickup.';
    if (!isOrderReady(now)) return 'The store is still preparing the order.';
    if (isStoreFixing(now)) {
      return 'The store is fixing the order. Check the items again when '
          'they hand it over.';
    }
    final left = uncheckedCount;
    if (left > 0) {
      return 'Check $left more ${left == 1 ? 'item' : 'items'} to confirm '
          'pickup.';
    }
    return null;
  }

  DeliveryTrip copyWith({
    List<DeliveryTask>? tasks,
    int? currentTaskIndex,
    TripStatus? status,
    List<GeoPoint>? routeSnapshot,
    DateTime? waitStartedAt,
    int? waitingPaise,
    Set<OfferTag>? checkedTags,
    bool? bagSealed,
    Object? bagPhoto = _keep,
    DateTime? orderReadyAt,
    DateTime? storeFixingUntil,
    TripCancellation? cancellation,
    Object? notice = _keep,
  }) => DeliveryTrip(
    id: id,
    offerId: offerId,
    store: store,
    tasks: tasks ?? this.tasks,
    acceptedAt: acceptedAt,
    startPosition: startPosition,
    currentTaskIndex: currentTaskIndex ?? this.currentTaskIndex,
    status: status ?? this.status,
    routeSnapshot: routeSnapshot ?? this.routeSnapshot,
    waitStartedAt: waitStartedAt ?? this.waitStartedAt,
    waitingPaise: waitingPaise ?? this.waitingPaise,
    pickupCode: pickupCode,
    tags: tags,
    checkedTags: checkedTags ?? this.checkedTags,
    bagSealed: bagSealed ?? this.bagSealed,
    bagPhoto: identical(bagPhoto, _keep)
        ? this.bagPhoto
        : bagPhoto as MediaRef?,
    orderReadyAt: orderReadyAt ?? this.orderReadyAt,
    storeFixingUntil: storeFixingUntil ?? this.storeFixingUntil,
    cancellation: cancellation ?? this.cancellation,
    notice: identical(notice, _keep) ? this.notice : notice as TripNotice?,
  );

  /// Applies [change] to every task (used for shared pickup steps).
  DeliveryTrip updateAllTasks(DeliveryTask Function(DeliveryTask) change) =>
      copyWith(tasks: tasks.map(change).toList());

  DeliveryTrip updateCurrentTask(DeliveryTask Function(DeliveryTask) change) {
    final updated = [...tasks];
    updated[currentTaskIndex] = change(updated[currentTaskIndex]);
    return copyWith(tasks: updated);
  }

  @override
  bool operator ==(Object other) =>
      other is DeliveryTrip &&
      other.id == id &&
      other.status == status &&
      other.currentTaskIndex == currentTaskIndex &&
      _sameTasks(other.tasks, tasks) &&
      _sameTags(other.checkedTags, checkedTags) &&
      other.bagSealed == bagSealed &&
      other.bagPhoto == bagPhoto &&
      other.waitStartedAt == waitStartedAt &&
      other.orderReadyAt == orderReadyAt &&
      other.storeFixingUntil == storeFixingUntil &&
      other.cancellation == cancellation &&
      other.notice == notice;

  @override
  int get hashCode => Object.hash(
    id,
    status,
    currentTaskIndex,
    Object.hashAll(tasks),
    checkedTags.length,
    bagSealed,
    orderReadyAt,
    storeFixingUntil,
  );

  @override
  String toString() =>
      'DeliveryTrip($id, ${status.name}, task ${currentTaskIndex + 1}/${tasks.length})';
}

bool _sameTasks(List<DeliveryTask> a, List<DeliveryTask> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameTags(Set<OfferTag> a, Set<OfferTag> b) =>
    a.length == b.length && a.containsAll(b);
