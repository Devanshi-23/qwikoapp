import 'dart:async';
import 'dart:math';

import '../../core/clock.dart';
import '../../core/domain_events.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../core/validators.dart';
import '../../models/activity.dart';
import '../../models/app_link.dart';
import '../../models/geo_point.dart';
import '../../models/money.dart';
import '../../models/notification.dart';
import '../../models/order.dart';
import '../../models/partner.dart';
import '../../models/trip.dart';
import '../../models/zone.dart';
import '../repositories/demo_controls.dart';
import 'demo_database.dart';
import 'demo_engine.dart';
import 'demo_order_factory.dart';
import 'demo_seed.dart';

/// Shared state behind every demo repository: the in-memory database plus
/// clock, engine and event bus.
class DemoBackend implements DemoControls {
  DemoBackend({
    required this.clock,
    required this.engine,
    required this.events,
    this.seed = DemoSeed.defaultSeed,
    this.firstOfferDelay = const Duration(seconds: 3),
    this.offerInterval = const Duration(seconds: 20),
    this.offerTakenAfter = const Duration(seconds: 4),
  }) : ids = IdGenerator(seed: seed),
       factory = DemoOrderFactory(Random(seed + 100)),
       db = DemoSeed.build(now: clock.now(), seed: seed);

  final Clock clock;
  final DemoEngine engine;
  final DomainEventBus events;
  final int seed;
  final Duration firstOfferDelay;
  final Duration offerInterval;

  /// How long a "taken by someone else" offer stays on screen before it is
  /// withdrawn.
  final Duration offerTakenAfter;
  final IdGenerator ids;
  final DemoOrderFactory factory;
  DemoDatabase db;
  DemoAccount _account = DemoAccount.verified;

  /// Rebuilds all demo data from the seed for the current account state.
  void reset() {
    final signedIn = db.signedIn;
    db = _build();
    db.signedIn = signedIn;
    takeNextOffer = false;
    customerResponse = CustomerResponse.answers;
    upiPaymentFails = false;
    tipAfterDelivery = true;
    payoutFails = false;
    _failingPayouts.clear();
    rejectNextDocument = false;
    _reviewDue.clear();
    _rejectOnReview.clear();
    engine.failNextRequest = false;
    events.emit(const DataReset());
  }

  DemoDatabase _build() {
    final fresh = DemoSeed.build(now: clock.now(), seed: seed);
    final partner = DemoSeed.partnerFor(_account, clock.now());
    switch (_account) {
      case DemoAccount.verified:
        break;
      case DemoAccount.suspended:
        fresh.partner = partner;
      case DemoAccount.newSignup ||
          DemoAccount.pending ||
          DemoAccount.rejectedDocument:
        fresh.startFresh(partner);
    }
    return fresh;
  }

  @override
  void resetData() => reset();

  @override
  DemoAccount get account => _account;

  @override
  void useAccount(DemoAccount account) {
    _account = account;
    reset();
  }

  void _updatePartner(
    VerificationStatus from,
    PartnerProfile Function(PartnerProfile partner) change,
  ) {
    if (db.partner.verification != from) return;
    db.partner = change(db.partner);
    events.emit(const ProfileChanged());
  }

  @override
  void approveVerification() => _updatePartner(
    VerificationStatus.pending,
    (p) => p.copyWith(
      verification: VerificationStatus.verified,
      documents: [
        for (final doc in p.documents)
          doc.status == DocumentStatus.pending
              ? doc.copyWith(status: DocumentStatus.verified)
              : doc,
      ],
    ),
  );

  @override
  void rejectVerification() => _updatePartner(
    VerificationStatus.pending,
    (p) => p.copyWith(
      verification: VerificationStatus.rejected,
      documents: [
        ...p.documents.where((d) => d.type != DocumentType.aadhaar),
        p
            .documentFor(DocumentType.aadhaar)
            .copyWith(
              status: DocumentStatus.rejected,
              rejectionReason: DemoSeed.rejectedAadhaarReason,
            ),
      ],
    ),
  );

  @override
  void reinstateAccount() => _updatePartner(
    VerificationStatus.suspended,
    (p) => p.copyWith(
      verification: VerificationStatus.verified,
      clearSuspensionReason: true,
    ),
  );

  @override
  void expireDocument() {
    final partner = db.partner;
    final required = partner.requiredDocuments;
    final type = required.contains(DocumentType.license)
        ? DocumentType.license
        : DocumentType.aadhaar;
    final doc = partner.documentFor(type);
    if (!doc.isUploaded) return;
    db.partner = partner.copyWith(
      documents: [
        ...partner.documents.where((d) => d.type != type),
        doc.copyWith(
          status: DocumentStatus.expired,
          expiresOn: startOfDay(clock.now()),
        ),
      ],
    );
    notify(
      NotificationCategory.account,
      '${type.title} expired',
      'Upload a new ${type.title.toLowerCase()} to go online again.',
      link: AppLink(AppLinkRoute.document, type.name),
    );
    events.emit(const ProfileChanged());
  }

  @override
  void setCashInHand(int paise) {
    final difference = paise - db.cash.balancePaise;
    if (difference == 0) return;
    final now = clock.now();
    if (difference > 0) {
      db.cash = db.cash.copyWith(
        movements: [
          ...db.cash.movements,
          CashMovement(
            type: CashMovementType.codCollected,
            amountPaise: difference,
            at: now,
          ),
        ],
      );
    } else {
      db.cash = db.cash.copyWith(
        movements: [
          ...db.cash.movements,
          CashMovement(
            type: CashMovementType.deposit,
            amountPaise: -difference,
            at: now,
          ),
        ],
        deposits: [
          ...db.cash.deposits,
          CashDeposit(
            id: ids.next('dep'),
            amountPaise: -difference,
            at: now,
            method: DepositMethod.storeCounter,
            reference: ids.reference('DEP'),
          ),
        ],
      );
    }
    events.emit(const WalletChanged());
  }

  final StreamController<OfferRequest> _offerRequests =
      StreamController<OfferRequest>.broadcast();

  /// Offers requested from Demo Controls; the offer feed turns them into
  /// offers for the rider's position.
  Stream<OfferRequest> get offerRequests => _offerRequests.stream;

  @override
  bool sendOffer(OfferRequest request) {
    if (!_offerRequests.hasListener) return false;
    _offerRequests.add(request);
    return true;
  }

  @override
  bool takeNextOffer = false;

  DemandOverride _demand = DemandOverride.schedule;

  @override
  DemandOverride get demandOverride => _demand;

  @override
  set demandOverride(DemandOverride value) {
    if (value == _demand) return;
    _demand = value;
    events.emit(const DemandChanged());
  }

  /// Zones with demand for [now]: busy at lunch (12–3 PM) and dinner
  /// (7–11 PM) unless Demo Controls force a level.
  List<DeliveryZone> zonesAt(DateTime now) {
    final hour = now.hour;
    final peak = (hour >= 12 && hour < 15) || (hour >= 19 && hour < 23);
    final level = switch (_demand) {
      DemandOverride.schedule => peak ? DemandOverride.high : null,
      final forced => forced,
    };
    return [
      for (final zone in db.zones)
        switch (_demandFor(zone.id, level)) {
          (final demand, final multiplier) => zone.copyWith(
            demand: demand,
            surgeMultiplier: multiplier,
          ),
        },
    ];
  }

  static (DemandLevel, double) _demandFor(
    String zoneId,
    DemandOverride? level,
  ) => switch ((level, zoneId)) {
    (DemandOverride.low, _) => (DemandLevel.low, 1.0),
    (DemandOverride.high, 'cp') => (DemandLevel.high, 1.3),
    (DemandOverride.high, 'kb') => (DemandLevel.high, 1.2),
    (DemandOverride.surge, 'cp') => (DemandLevel.surge, 1.6),
    (DemandOverride.surge, 'kb') => (DemandLevel.high, 1.3),
    (DemandOverride.surge, 'sk') => (DemandLevel.high, 1.2),
    _ => (DemandLevel.normal, 1.0),
  };

  /// The zone whose centre is closest to [position].
  DeliveryZone zoneNearest(GeoPoint position) {
    final zones = zonesAt(clock.now());
    return zones.reduce(
      (a, b) =>
          position.distanceMetersTo(a.center) <=
              position.distanceMetersTo(b.center)
          ? a
          : b,
    );
  }

  @override
  bool get networkAvailable => engine.networkAvailable;

  @override
  set networkAvailable(bool value) {
    if (value == engine.networkAvailable) return;
    engine.networkAvailable = value;
    if (value) _syncQueuedSteps();
    events.emit(const DeviceChanged());
  }

  /// Trip steps taken offline reach the server once the network is back.
  void _syncQueuedSteps() {
    DeliveryTask synced(DeliveryTask task) => task.copyWith(
      timeline: [
        for (final event in task.timeline)
          event.queued ? event.synced() : event,
      ],
    );
    for (var i = 0; i < db.history.length; i++) {
      final task = db.history[i];
      if (task.timeline.any((e) => e.queued)) db.history[i] = synced(task);
    }
    final trip = db.activeTrip;
    if (trip == null || !trip.hasQueuedSteps) return;
    db.activeTrip = trip.updateAllTasks(synced);
    events.emit(const TripChanged());
  }

  /// Ends [trip] before pickup and works out compensation (plan 3.8.3).
  /// The trip stays active, cancelled, until the rider acknowledges it.
  DeliveryTrip cancelTrip(
    DeliveryTrip trip, {
    required CancelledBy by,
    required String reason,
    required bool atStore,
    int travelledM = 0,
  }) {
    final now = clock.now();
    final paid = atStore || travelledM > DeliveryTrip.compensationMinTravelM;
    final waiting = trip.waitingPaiseAt(now);
    final cancelled = trip.copyWith(
      status: TripStatus.cancelled,
      waitingPaise: waiting,
      cancellation: TripCancellation(
        by: by,
        reason: reason,
        at: now,
        atStore: atStore,
        compensationPaise: paid ? DeliveryTrip.storeTripCompensationPaise : 0,
        waitingPaise: waiting,
      ),
    );
    db.activeTrip = cancelled;
    events.emit(const TripChanged());
    return cancelled;
  }

  @override
  CustomerResponse customerResponse = CustomerResponse.answers;

  @override
  bool upiPaymentFails = false;

  @override
  bool tipAfterDelivery = true;

  static const payoutProcessingAfter = Duration(seconds: 5);
  static const payoutSettlesAfter = Duration(seconds: 20);
  static const rainBonusId = 'inc-rain';
  static const rainBonusFor = Duration(hours: 2);

  @override
  bool payoutFails = false;

  final Set<String> _failingPayouts = {};

  /// Earned and not yet paid out (failed payouts give the money back).
  int get withdrawablePaise {
    final earned = db.ledger.fold(0, (sum, e) => sum + e.amountPaise);
    final paidOut = db.payouts
        .where((p) => p.status != PayoutStatus.failed)
        .fold(0, (sum, p) => sum + p.amountPaise);
    return earned - paidOut;
  }

  /// Records [payout] as requested; it moves to processing after
  /// [payoutProcessingAfter] and settles after [payoutSettlesAfter].
  void startPayout(Payout payout) {
    db.payouts.insert(0, payout);
    if (payoutFails) _failingPayouts.add(payout.id);
    for (final delay in [payoutProcessingAfter, payoutSettlesAfter]) {
      Timer(delay, () {
        if (!events.isClosed) settlePayouts();
      });
    }
  }

  /// Moves in-flight payouts along by the clock. Returns whether any
  /// changed.
  bool settlePayouts() {
    final now = clock.now();
    var changed = false;
    for (var i = 0; i < db.payouts.length; i++) {
      final payout = db.payouts[i];
      if (!payout.status.isInFlight) continue;
      final elapsed = now.difference(payout.requestedAt);
      final PayoutStatus status;
      if (elapsed >= payoutSettlesAfter) {
        status = _failingPayouts.contains(payout.id)
            ? PayoutStatus.failed
            : PayoutStatus.paid;
      } else if (elapsed >= payoutProcessingAfter) {
        status = PayoutStatus.processing;
      } else {
        continue;
      }
      if (status == payout.status) continue;
      changed = true;
      db.payouts[i] = payout.copyWith(
        status: status,
        failureReason: status == PayoutStatus.failed
            ? 'The bank declined the transfer. The money is back in your '
                  'balance; try again.'
            : null,
      );
      if (status == PayoutStatus.paid) {
        notify(
          NotificationCategory.earnings,
          '${formatPaise(payout.amountPaise)} sent to your bank',
          'Ref ${payout.reference}',
          link: AppLink(AppLinkRoute.payout, payout.id),
        );
      } else if (status == PayoutStatus.failed) {
        notify(
          NotificationCategory.earnings,
          'Payout of ${formatPaise(payout.amountPaise)} failed',
          'The bank declined it. The money is back in your balance.',
          link: AppLink(AppLinkRoute.payout, payout.id),
        );
      }
    }
    if (changed) events.emit(const WalletChanged());
    return changed;
  }

  @override
  Payout? runWeeklyPayout() {
    settlePayouts();
    final amount = withdrawablePaise;
    if (amount < Validators.minWithdrawPaise) return null;
    final payout = Payout(
      id: ids.next('pay'),
      amountPaise: amount,
      requestedAt: clock.now(),
      status: PayoutStatus.requested,
      reference: ids.reference('TXN'),
      isScheduled: true,
    );
    startPayout(payout);
    recordActivity(
      ActivityType.payoutRequested,
      'Weekly · ${payout.reference}',
    );
    events.emit(const WalletChanged());
    return payout;
  }

  static const reviewTakes = Duration(seconds: 10);
  static const bankReviewKey = 'bank';

  @override
  bool rejectNextDocument = false;

  final Map<String, DateTime> _reviewDue = {};
  final Set<String> _rejectOnReview = {};

  /// Starts the demo review of the bank account ([bankReviewKey]) or a
  /// document (its type name); it finishes after [reviewTakes].
  void startReview(String key, {bool reject = false}) {
    _reviewDue[key] = clock.now().add(reviewTakes);
    reject ? _rejectOnReview.add(key) : _rejectOnReview.remove(key);
    Timer(reviewTakes, () {
      if (!events.isClosed) settleReviews();
    });
  }

  /// Finishes reviews that are due. Returns whether the profile changed.
  bool settleReviews() {
    final now = clock.now();
    var partner = db.partner;
    var changed = false;
    for (final MapEntry(:key, value: due) in [..._reviewDue.entries]) {
      if (now.isBefore(due)) continue;
      _reviewDue.remove(key);
      final reject = _rejectOnReview.remove(key);
      if (key == bankReviewKey) {
        final bank = partner.bank;
        if (bank == null || bank.verification != BankVerification.verifying) {
          continue;
        }
        partner = partner.copyWith(
          bank: bank.copyWith(
            verification: reject
                ? BankVerification.failed
                : BankVerification.verified,
          ),
        );
        notify(
          NotificationCategory.account,
          reject ? "We couldn't verify your bank account" : 'Bank verified',
          reject
              ? 'Check the account number and IFSC, then save again.'
              : '${bank.bankName} ${bank.maskedAccountNumber} can now '
                    'receive payouts.',
        );
      } else {
        final type = DocumentType.values.byName(key);
        final doc = partner.documentFor(type);
        if (doc.status != DocumentStatus.pending) continue;
        partner = partner.copyWith(
          documents: [
            ...partner.documents.where((d) => d.type != type),
            doc.copyWith(
              status: reject
                  ? DocumentStatus.rejected
                  : DocumentStatus.verified,
              rejectionReason: reject ? DemoSeed.rejectedAadhaarReason : null,
            ),
          ],
        );
        notify(
          NotificationCategory.account,
          reject ? '${type.title} rejected' : '${type.title} verified',
          reject
              ? DemoSeed.rejectedAadhaarReason
              : 'Thanks! Your ${type.title.toLowerCase()} is verified.',
          link: AppLink(AppLinkRoute.document, type.name),
        );
      }
      changed = true;
    }
    if (changed) {
      db.partner = partner;
      events.emit(const ProfileChanged());
    }
    return changed;
  }

  @override
  bool get raining => db.incentives.any(
    (i) => i.id == rainBonusId && clock.now().isBefore(i.windowEnd),
  );

  @override
  set raining(bool value) {
    if (value == raining) return;
    final now = clock.now();
    if (value) {
      db.incentives.removeWhere((i) => i.id == rainBonusId);
      db.incentives.insert(
        0,
        Incentive(
          id: rainBonusId,
          type: IncentiveType.rainBonus,
          title: 'Rain bonus',
          tiers: const [IncentiveTier(target: 1, rewardPaise: 1500)],
          windowStart: now,
          windowEnd: now.add(rainBonusFor),
          status: IncentiveStatus.active,
          terms:
              '₹15 extra for every order delivered while it rains. Ends '
              'when the rain stops or after two hours.',
        ),
      );
      notify(
        NotificationCategory.incentive,
        "It's raining: ₹15 extra per order",
        'Ride carefully. The rain bonus runs for the next two hours.',
        link: const AppLink(AppLinkRoute.incentive, rainBonusId),
      );
    } else {
      final i = db.incentives.indexWhere((i) => i.id == rainBonusId);
      final ended = db.incentives[i].copyWith(windowEnd: now);
      db.incentives[i] = ended.copyWith(status: ended.statusAt(now));
    }
    events.emit(const IncentivesChanged());
  }

  @override
  String? get customerOtp {
    final trip = db.activeTrip;
    if (trip == null || !trip.isPickedUp) return null;
    final task = trip.currentTask;
    return task.status.isFinal ? null : task.deliveryOtp;
  }

  /// Adds a notification and tells listeners.
  void notify(
    NotificationCategory category,
    String title,
    String body, {
    AppLink? link,
  }) {
    if (!db.settings.allows(category)) return;
    db.notifications.insert(
      0,
      AppNotification(
        id: ids.next('ntf'),
        category: category,
        title: title,
        body: body,
        at: clock.now(),
        deepLink: link,
      ),
    );
    events.emit(const NotificationsChanged());
  }

  void creditLedger(EarningType type, int amountPaise, DeliveryTask task) {
    if (amountPaise <= 0) return;
    db.ledger.insert(
      0,
      EarningEntry(
        id: ids.next('led'),
        type: type,
        amountPaise: amountPaise,
        at: clock.now(),
        orderId: task.orderId,
        label: '${type.label} · ${task.displayId}',
      ),
    );
  }

  /// Moves an order that ended without delivery to history and credits
  /// what it earned.
  void closeTask(DeliveryTask task, {PayoutBreakdown? payout}) {
    final closed = payout == null ? task : task.copyWith(payout: payout);
    creditLedger(
      EarningType.compensation,
      closed.payout.compensationPaise,
      closed,
    );
    creditLedger(EarningType.waitingPay, closed.payout.waitingPaise, closed);
    db.history.insert(0, closed);
    final reason = closed.timeline.isEmpty ? null : closed.timeline.last.note;
    recordActivity(
      ActivityType.cancelled,
      reason == null ? closed.displayId : '${closed.displayId} · $reason',
    );
    events.emit(OrderCompleted(closed.orderId));
  }

  /// The drop at [index] won't be delivered (plan 3.8.3). A returnable
  /// order goes back to the store after the remaining drops; any other is
  /// disposed of as instructed and paid now. Returns the trip moved on to
  /// its next leg, or null when it is over.
  DeliveryTrip? failDrop(
    DeliveryTrip trip,
    int index, {
    required String reason,
    bool queued = false,
  }) {
    final now = clock.now();
    final task = trip.tasks[index];
    final waiting = index == 0 ? trip.waitingPaise : 0;
    final returnable = task.isReturnable;
    final pay = task.failedPayout(returned: returnable, waitingPaise: waiting);
    final DeliveryTask failed;
    final TripNotice notice;
    if (returnable) {
      failed = task.transition(
        OrderStatus.returningToStore,
        now,
        event: OrderEventType.returningToStore,
        note: reason,
        queued: queued,
      );
      notice = TripNotice(
        title: 'Return ${task.displayId} to the store',
        message:
            '$reason Take the order back to ${trip.store.name}. You get '
            '${formatPaise(pay.totalPaise)} once it is returned.',
      );
    } else {
      failed = task
          .transition(
            OrderStatus.disposed,
            now,
            event: OrderEventType.cancelled,
            note: reason,
            queued: queued,
          )
          .copyWith(payout: pay);
      closeTask(failed);
      events.emit(const LedgerChanged());
      notice = TripNotice(
        title: 'Keep or dispose as instructed',
        message:
            '$reason ${task.displayId} has perishable or pharmacy items, so '
            "it can't go back to the store. Dispose of it safely as the store "
            'instructs. ${formatPaise(pay.totalPaise)} is added to your '
            'earnings.',
      );
    }
    final updated = trip.copyWith(
      tasks: [...trip.tasks]..[index] = failed,
      notice: notice,
    );
    return nextLeg(updated, now);
  }

  /// After a drop ends: the next undelivered drop, then any return to the
  /// store. A trip with a notice to read waits as `completed`; otherwise
  /// null means the trip is over.
  DeliveryTrip? nextLeg(DeliveryTrip trip, DateTime now) {
    final next = trip.tasks.indexWhere(
      (t) =>
          t.status == OrderStatus.pickedUp ||
          t.status == OrderStatus.headingToCustomer ||
          t.status == OrderStatus.arrivedAtCustomer,
    );
    if (next >= 0) {
      final moved = trip.copyWith(
        currentTaskIndex: next,
        status: TripStatus.inProgress,
      );
      return moved.currentTask.status == OrderStatus.pickedUp
          ? moved.updateCurrentTask(
              (t) => t.transition(OrderStatus.headingToCustomer, now),
            )
          : moved;
    }
    final returning = trip.tasks.indexWhere(
      (t) => t.status == OrderStatus.returningToStore,
    );
    if (returning >= 0) {
      return trip.copyWith(
        currentTaskIndex: returning,
        status: TripStatus.returningToStore,
      );
    }
    if (trip.notice != null) return trip.copyWith(status: TripStatus.completed);
    return null;
  }

  @override
  bool cancelActiveTrip(CancelledBy by, {int travelledM = 0}) {
    final trip = db.activeTrip;
    if (trip == null) return false;
    if (trip.isPickedUp) {
      final status = trip.currentTask.status;
      final onTheWay =
          status == OrderStatus.headingToCustomer ||
          status == OrderStatus.arrivedAtCustomer;
      if (by == CancelledBy.store || !onTheWay) return false;
      db.activeTrip = failDrop(
        trip,
        trip.currentTaskIndex,
        reason: by == CancelledBy.customer
            ? 'The customer cancelled the order.'
            : 'Qwiko cancelled the order.',
      );
      events.emit(const TripChanged());
      return true;
    }
    final atStore = trip.status == TripStatus.atStore;
    if (!atStore && trip.status != TripStatus.headingToStore) return false;
    cancelTrip(
      trip,
      by: by,
      reason: switch (by) {
        CancelledBy.customer => 'The customer cancelled the order.',
        CancelledBy.store =>
          'The store cancelled the order. Items are out '
              'of stock.',
        CancelledBy.system => 'Qwiko cancelled the order.',
      },
      atStore: atStore,
      travelledM: travelledM,
    );
    return true;
  }

  @override
  bool skipStoreWait() {
    final trip = db.activeTrip;
    if (trip == null || trip.status != TripStatus.atStore) return false;
    final now = clock.now();
    final readyIn = trip.isOrderReady(now)
        ? Duration.zero
        : trip.orderReadyAt!.difference(now);
    final fixIn = trip.isStoreFixing(now)
        ? trip.storeFixingUntil!.difference(now)
        : Duration.zero;
    final skipped = readyIn > fixIn ? readyIn : fixIn;
    if (skipped == Duration.zero) return false;
    db.activeTrip = trip
        .copyWith(
          waitStartedAt: trip.waitStartedAt?.subtract(skipped),
          orderReadyAt: readyIn > Duration.zero ? now : null,
          storeFixingUntil: fixIn > Duration.zero ? now : null,
        )
        .updateAllTasks(
          (task) => task.record(
            OrderEventType.issueReported,
            now,
            note: 'Store wait skipped (demo)',
          ),
        );
    events.emit(const TripChanged());
    return true;
  }

  bool _locationGranted = true;

  @override
  bool get locationPermissionGranted => _locationGranted;

  @override
  set locationPermissionGranted(bool value) {
    if (value == _locationGranted) return;
    _locationGranted = value;
    events.emit(const DeviceChanged());
  }

  bool _locationService = true;

  @override
  bool get locationServiceEnabled => _locationService;

  @override
  set locationServiceEnabled(bool value) {
    if (value == _locationService) return;
    _locationService = value;
    events.emit(const DeviceChanged());
  }

  @override
  Duration get latency => engine.latency;

  @override
  set latency(Duration value) => engine.latency = value;

  @override
  double get speed => switch (clock) {
    final DemoClock demoClock => demoClock.speed,
    _ => 1,
  };

  @override
  set speed(double value) {
    final current = clock;
    if (current is DemoClock) current.speed = value;
  }

  @override
  void failNext(OperationType operation) => engine.failNext(operation);

  @override
  void failNextRequest() => engine.failNextRequest = true;

  void recordActivity(ActivityType type, [String details = '']) {
    db.activity.add(
      ActivityEvent(
        id: ids.next('act'),
        type: type,
        at: clock.now(),
        details: details,
      ),
    );
    events.emit(const ActivityChanged());
  }
}
