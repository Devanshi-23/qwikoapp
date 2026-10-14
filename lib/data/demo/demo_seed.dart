import 'dart:math';

import '../../core/clock.dart';
import '../../core/formatters.dart';
import '../../models/activity.dart';
import '../../models/announcement.dart';
import '../../models/app_link.dart';
import '../../models/media_ref.dart';
import '../../models/money.dart';
import '../../models/notification.dart';
import '../../models/order.dart';
import '../../models/partner.dart';
import '../../models/support.dart';
import '../repositories/demo_controls.dart';
import 'demo_catalog.dart';
import 'demo_database.dart';
import 'demo_order_factory.dart';

/// Deterministic demo data: the same seed and "now" always give the same
/// partner, 60 days of history, ledger, payouts and notifications.
class DemoSeed {
  DemoSeed._();

  static const int defaultSeed = 42;
  static const int historyDays = 60;
  static const int firstOrderNumber = 1000;

  static DemoDatabase build({required DateTime now, int seed = defaultSeed}) =>
      _SeedBuilder(now, seed).build();

  static PartnerProfile defaultPartner(DateTime now) => PartnerProfile(
    id: 'P-1001',
    name: 'Arjun Mehta',
    phone: '9876543210',
    email: 'arjun.mehta@example.com',
    address: 'H-24, Lajpat Nagar III, New Delhi',
    rating: const RatingSummary(
      average: 4.8,
      count: 1240,
      distribution: [8, 10, 28, 150, 1044],
      recentCompliments: [
        'Very polite',
        'Delivered before time',
        'Handled items with care',
      ],
      tips: [
        'Call the customer if the gate is closed',
        'Keep cold items in the insulated bag',
      ],
    ),
    joinedOn: DateTime(now.year, now.month - 14, now.day),
    verification: VerificationStatus.verified,
    vehicle: const Vehicle(
      type: VehicleType.scooter,
      registrationNumber: 'DL 3S AB 4821',
      model: 'Honda Activa 6G',
    ),
    bank: const BankAccount(
      holderName: 'Arjun Mehta',
      accountNumber: '50100234564821',
      ifsc: 'HDFC0001234',
      bankName: 'HDFC Bank',
    ),
    upiId: 'arjun.mehta@okhdfcbank',
    documents: [
      for (final type in DocumentType.values)
        type == DocumentType.insurance
            ? PartnerDocument(
                type: type,
                status: DocumentStatus.expiringSoon,
                expiresOn: DateTime(now.year, now.month, now.day + 12),
                media: MediaRef.sample('doc-${type.name}'),
              )
            : PartnerDocument(
                type: type,
                status: DocumentStatus.verified,
                media: MediaRef.sample('doc-${type.name}'),
                expiresOn: switch (type) {
                  DocumentType.license => DateTime(now.year + 3, now.month),
                  DocumentType.pucc => DateTime(now.year, now.month + 5),
                  _ => null,
                },
              ),
    ],
    emergencyContacts: const [
      EmergencyContact(
        name: 'Sunita Mehta',
        relation: 'Mother',
        phone: '9811122334',
      ),
    ],
    homeZoneId: 'ln',
  );

  static const String rejectedAadhaarReason =
      'The photo is blurry. Upload a clear photo with all four corners '
      'visible.';

  static const String suspensionReason =
      'Your account is on hold after repeated customer complaints about '
      'late deliveries. Our team will review it within 48 hours.';

  /// The partner for each demo account state. Every state is the same
  /// person at a different stage, so the phone number stays the same.
  static PartnerProfile partnerFor(DemoAccount account, DateTime now) {
    final verified = defaultPartner(now);
    final newSignup = PartnerProfile(
      id: verified.id,
      name: verified.name,
      phone: verified.phone,
      email: verified.email,
      joinedOn: startOfDay(now),
      homeZoneId: verified.homeZoneId,
    );
    PartnerProfile submitted(VerificationStatus status) => newSignup.copyWith(
      verification: status,
      vehicle: verified.vehicle,
      bank: verified.bank,
      upiId: verified.upiId,
      documents: [
        for (final type in verified.requiredDocuments)
          PartnerDocument(
            type: type,
            status:
                status == VerificationStatus.rejected &&
                    type == DocumentType.aadhaar
                ? DocumentStatus.rejected
                : DocumentStatus.pending,
            rejectionReason: type == DocumentType.aadhaar
                ? rejectedAadhaarReason
                : null,
            media: MediaRef.sample('doc-${type.name}'),
          ),
      ],
    );
    return switch (account) {
      DemoAccount.verified => verified,
      DemoAccount.newSignup => newSignup,
      DemoAccount.pending => submitted(VerificationStatus.pending),
      DemoAccount.rejectedDocument => submitted(VerificationStatus.rejected),
      DemoAccount.suspended => verified.copyWith(
        verification: VerificationStatus.suspended,
        suspensionReason: suspensionReason,
      ),
    };
  }
}

class _SeedBuilder {
  _SeedBuilder(this.now, int seed)
    : _random = Random(seed),
      _factory = DemoOrderFactory(Random(seed + 1));

  final DateTime now;
  final Random _random;
  final DemoOrderFactory _factory;

  int _orderNumber = DemoSeed.firstOrderNumber;
  int _idCounter = 0;

  late final List<CustomerInfo> _customers;
  final List<DeliveryTask> _history = [];
  final List<EarningEntry> _ledger = [];
  final List<ActivityEvent> _activity = [];
  final List<CashMovement> _cashMovements = [];
  final List<CashDeposit> _deposits = [];

  static const List<String> _cancelReasons = [
    'Customer cancelled the order',
    'Store marked the order unavailable',
    'Items out of stock',
  ];

  String _id(String prefix) => '$prefix-${++_idCounter}';

  DemoDatabase build() {
    _customers = List.generate(40, (i) {
      final zone = demoZones[i % demoZones.length];
      return _factory.buildCustomer(i, zone.id, zone.center);
    });

    final today = startOfDay(now);
    for (var daysAgo = DemoSeed.historyDays; daysAgo >= 0; daysAgo--) {
      _seedDay(
        DateTime(today.year, today.month, today.day - daysAgo),
        isToday: daysAgo == 0,
      );
    }

    _history.sort((a, b) => b.lastUpdatedAt.compareTo(a.lastUpdatedAt));
    _ledger.sort((a, b) => b.at.compareTo(a.at));
    _activity.sort((a, b) => a.at.compareTo(b.at));

    final payouts = _seedPayouts();
    final partner = DemoSeed.defaultPartner(now);

    return DemoDatabase(
        partner: partner,
        zones: [...demoZones],
        stores: [...demoStores],
        customers: _customers,
        catalog: demoCatalog,
        history: _history,
        ledger: _ledger,
        payouts: payouts,
        cash: CashInHand(movements: _cashMovements, deposits: _deposits),
        notifications: _seedNotifications(payouts, partner),
        activity: _activity,
        tickets: _seedTickets(payouts),
        faqs: [...demoFaqs],
        incentives: _seedIncentives(),
        announcements: [
          const Announcement(
            id: 'ann-rain',
            kind: AnnouncementKind.weather,
            title: 'Rain expected from 6 PM',
            body:
                'Ride slowly, keep a rain cover for orders and avoid '
                'waterlogged underpasses.',
          ),
          const Announcement(
            id: 'ann-dinner-bonus',
            kind: AnnouncementKind.incentive,
            title: 'New: dinner peak bonus',
            body: 'Earn ₹10 extra on every order delivered from 7 PM to 11 PM.',
            link: AppLink(AppLinkRoute.incentive, 'inc-peak'),
            linkLabel: 'View incentive',
          ),
        ],
        nextOrderNumber: _orderNumber,
      )
      ..incidents.add(
        SafetyIncident(
          id: 'INC-101',
          type: SafetyIncidentType.vehicleBreakdown,
          at: now.subtract(const Duration(days: 9, hours: 3)),
          description:
              'Front tyre punctured near Moolchand flyover. Pushed the scooter '
              'to a repair shop and the order was reassigned.',
          status: IncidentStatus.resolved,
          resolvedAt: now.subtract(const Duration(days: 9, hours: 1)),
        ),
      );
  }

  void _seedDay(DateTime day, {required bool isToday}) {
    final weekend = day.weekday >= DateTime.saturday;
    final count = (weekend ? 8 : 6) + _random.nextInt(4);
    final lunch = count ~/ 2;
    final sessions = [
      (day.add(const Duration(hours: 11, minutes: 20)), lunch),
      (day.add(const Duration(hours: 18, minutes: 30)), count - lunch),
    ];

    var deliveredToday = 0;
    var codToday = 0;

    for (final (start, orders) in sessions) {
      if (start.isAfter(now)) continue;
      _activity.add(
        ActivityEvent(id: _id('act'), type: ActivityType.wentOnline, at: start),
      );
      var lastEnd = start;

      for (var i = 0; i < orders; i++) {
        final offeredAt = start.add(
          Duration(minutes: 10 + i * 38 + _random.nextInt(12)),
        );
        if (offeredAt.add(const Duration(minutes: 35)).isAfter(now)) break;

        if (_random.nextInt(100) < 12) {
          _activity.add(
            ActivityEvent(
              id: _id('act'),
              type: ActivityType.offerDeclined,
              at: offeredAt.subtract(const Duration(minutes: 4)),
              details: 'Too far',
            ),
          );
        } else if (_random.nextInt(100) < 5) {
          _activity.add(
            ActivityEvent(
              id: _id('act'),
              type: ActivityType.offerMissed,
              at: offeredAt.subtract(const Duration(minutes: 4)),
            ),
          );
        }

        final task = _seedOrder(offeredAt);
        _history.add(task);
        lastEnd = task.lastUpdatedAt;

        if (task.status == OrderStatus.delivered) {
          deliveredToday++;
          _creditMilestone(deliveredToday, lastEnd);
          _creditPeak(task, lastEnd);
          if (task.payment.isCod) {
            codToday += task.payment.amountToCollectPaise;
            _cashMovements.add(
              CashMovement(
                type: CashMovementType.codCollected,
                amountPaise: task.payment.amountToCollectPaise,
                at: lastEnd,
                orderId: task.orderId,
              ),
            );
          }
        }
      }

      var offlineAt = lastEnd.add(const Duration(minutes: 15));
      if (offlineAt.isAfter(now)) {
        offlineAt = now.subtract(const Duration(minutes: 1));
      }
      _activity.add(
        ActivityEvent(
          id: _id('act'),
          type: ActivityType.wentOffline,
          at: offlineAt,
        ),
      );
    }

    if (!isToday && codToday > 0) {
      final at = day.add(const Duration(hours: 22, minutes: 45));
      final id = _id('dep');
      _cashMovements.add(
        CashMovement(
          type: CashMovementType.deposit,
          amountPaise: codToday,
          at: at,
        ),
      );
      _deposits.add(
        CashDeposit(
          id: id,
          amountPaise: codToday,
          at: at,
          method: DepositMethod.storeCounter,
          reference: 'DEP${10000 + _random.nextInt(90000)}',
        ),
      );
    }
  }

  DeliveryTask _seedOrder(DateTime offeredAt) {
    final store = _factory.pick(demoStores);
    final customer = _factory.pick(
      _customers.where((c) => _zoneOf(c) == store.zoneId).toList(),
    );
    final hour = offeredAt.hour;
    final peak = (hour >= 12 && hour < 15) || (hour >= 19 && hour < 23);
    final surge = peak && _random.nextInt(100) < 30 ? 1.2 : 1.0;

    var task = _factory.buildTask(
      number: _orderNumber++,
      store: store,
      customer: customer,
      createdAt: offeredAt,
      distanceToPickupM: 500 + _random.nextInt(2000),
      surgeMultiplier: surge,
    );

    final at = offeredAt.add(const Duration(seconds: 20));
    task = task.transition(
      OrderStatus.accepted,
      at,
      event: OrderEventType.accepted,
    );
    _activity.add(
      ActivityEvent(
        id: _id('act'),
        type: ActivityType.offerAccepted,
        at: at,
        details: task.displayId,
      ),
    );

    final roll = _random.nextInt(100);
    if (roll < 92) return _deliver(task, at);
    if (roll < 97) return _cancel(task, at);
    return _return(task, at);
  }

  String _zoneOf(CustomerInfo customer) {
    for (final entry in demoLocalities.entries) {
      if (entry.value.contains(customer.locality)) return entry.key;
    }
    return demoZones.first.id;
  }

  DeliveryTask _deliver(DeliveryTask task, DateTime acceptedAt) {
    final arrivedStore = acceptedAt.add(
      Duration(minutes: 5 + _random.nextInt(4)),
    );
    final pickedUp = arrivedStore.add(
      Duration(minutes: 2 + _random.nextInt(4)),
    );
    final arrivedCustomer = pickedUp.add(
      Duration(minutes: DemoOrderFactory.minutesFor(task.distanceM)),
    );
    final deliveredAt = arrivedCustomer.add(
      Duration(minutes: 1 + _random.nextInt(3)),
    );

    final tipPaise = _random.nextInt(100) < 20
        ? [500, 1000, 1500, 2000, 3000][_random.nextInt(5)]
        : 0;

    final delivered = task
        .transition(
          OrderStatus.arrivedAtStore,
          arrivedStore,
          event: OrderEventType.arrivedAtStore,
        )
        .transition(
          OrderStatus.pickedUp,
          pickedUp,
          event: OrderEventType.pickedUp,
        )
        .transition(
          OrderStatus.arrivedAtCustomer,
          arrivedCustomer,
          event: OrderEventType.arrivedAtCustomer,
        )
        .transition(
          OrderStatus.delivered,
          deliveredAt,
          event: OrderEventType.delivered,
        )
        .copyWith(
          payout: task.payout.copyWith(tipPaise: tipPaise),
          proof: DeliveryProof(
            method: task.requiredProof,
            capturedAt: deliveredAt,
            otpVerified: task.requiredProof != ProofMethod.photo,
            photo: task.requiredProof == ProofMethod.otp
                ? null
                : const MediaRef.sample('door-photo'),
            cashCollectedPaise: task.payment.amountToCollectPaise,
            collectedVia: task.payment.isCod ? CollectionMethod.cash : null,
          ),
        );

    _credit(
      EarningType.orderPay,
      delivered.payout.orderPayPaise,
      deliveredAt,
      delivered,
    );
    _credit(
      EarningType.surge,
      delivered.payout.surgePaise,
      deliveredAt,
      delivered,
    );
    if (tipPaise > 0) {
      var tipAt = deliveredAt.add(Duration(minutes: 5 + _random.nextInt(40)));
      if (tipAt.isAfter(now)) tipAt = deliveredAt;
      _credit(EarningType.tip, tipPaise, tipAt, delivered);
    }
    _activity.add(
      ActivityEvent(
        id: _id('act'),
        type: ActivityType.delivered,
        at: deliveredAt,
        details: delivered.displayId,
      ),
    );
    return delivered;
  }

  DeliveryTask _cancel(DeliveryTask task, DateTime acceptedAt) {
    final cancelledAt = acceptedAt.add(
      Duration(minutes: 4 + _random.nextInt(5)),
    );
    final compensation = _random.nextInt(100) < 60 ? 1500 : 0;
    final cancelled = task
        .transition(
          OrderStatus.cancelled,
          cancelledAt,
          event: OrderEventType.cancelled,
          note: _cancelReasons[_random.nextInt(_cancelReasons.length)],
        )
        .copyWith(payout: PayoutBreakdown(compensationPaise: compensation));
    _credit(EarningType.compensation, compensation, cancelledAt, cancelled);
    _activity.add(
      ActivityEvent(
        id: _id('act'),
        type: ActivityType.cancelled,
        at: cancelledAt,
        details: cancelled.displayId,
      ),
    );
    return cancelled;
  }

  DeliveryTask _return(DeliveryTask task, DateTime acceptedAt) {
    final pickedUp = acceptedAt.add(const Duration(minutes: 9));
    final arrived = pickedUp.add(
      Duration(minutes: DemoOrderFactory.minutesFor(task.distanceM)),
    );
    final returning = arrived.add(const Duration(minutes: 7));
    final returnedAt = returning.add(
      Duration(minutes: DemoOrderFactory.minutesFor(task.distanceM)),
    );
    final compensation =
        ((task.payout.orderPayPaise * 0.5) / 100).round() * 100;

    final returned = task
        .transition(
          OrderStatus.pickedUp,
          pickedUp,
          event: OrderEventType.pickedUp,
        )
        .transition(
          OrderStatus.arrivedAtCustomer,
          arrived,
          event: OrderEventType.arrivedAtCustomer,
        )
        .transition(
          OrderStatus.returningToStore,
          returning,
          event: OrderEventType.returningToStore,
          note: 'Customer not reachable',
        )
        .transition(
          OrderStatus.returned,
          returnedAt,
          event: OrderEventType.returned,
        )
        .copyWith(payout: PayoutBreakdown(compensationPaise: compensation));
    _credit(EarningType.compensation, compensation, returnedAt, returned);
    return returned;
  }

  void _credit(
    EarningType type,
    int amountPaise,
    DateTime at,
    DeliveryTask task,
  ) {
    if (amountPaise <= 0) return;
    _ledger.add(
      EarningEntry(
        id: _id('led'),
        type: type,
        amountPaise: amountPaise,
        at: at,
        orderId: task.orderId,
        label: '${type.label} · ${task.displayId}',
      ),
    );
  }

  /// Daily milestones: 8 → ₹80, 14 → ₹180, 20 → ₹300 in total.
  void _creditMilestone(int delivered, DateTime at) {
    final reward = switch (delivered) {
      8 => 8000,
      14 => 10000,
      20 => 12000,
      _ => 0,
    };
    if (reward == 0) return;
    _ledger.add(
      EarningEntry(
        id: _id('led'),
        type: EarningType.incentive,
        amountPaise: reward,
        at: at,
        label: 'Daily milestone · $delivered orders',
      ),
    );
  }

  /// Peak-hour bonus: ₹10 per order delivered 12–3 PM or 7–11 PM.
  void _creditPeak(DeliveryTask task, DateTime at) {
    final title = switch (at.hour) {
      >= 12 && < 15 => 'Lunch peak bonus',
      >= 19 && < 23 => 'Dinner peak bonus',
      _ => null,
    };
    if (title == null) return;
    _ledger.add(
      EarningEntry(
        id: _id('led'),
        type: EarningType.incentive,
        amountPaise: 1000,
        at: at,
        label: '$title · ${task.displayId}',
      ),
    );
  }

  List<Payout> _seedPayouts() {
    final today = startOfDay(now);
    final mondays = <DateTime>[];
    for (var week = 0; mondays.length < 8; week++) {
      final monday = DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - DateTime.monday) - 7 * week,
        6,
      );
      if (!monday.isAfter(now)) mondays.add(monday);
    }
    mondays.sort();

    final payouts = <Payout>[];
    DateTime? previous;
    for (var i = 0; i < mondays.length; i++) {
      final boundary = mondays[i];
      final amount = _ledger
          .where(
            (e) =>
                e.at.isBefore(boundary) &&
                (previous == null || !e.at.isBefore(previous)),
          )
          .fold(0, (sum, e) => sum + e.amountPaise);
      previous = boundary;
      if (amount <= 0) continue;

      final failedOnce = i == mondays.length - 3;
      if (failedOnce) {
        payouts.add(
          Payout(
            id: _id('pay'),
            amountPaise: amount,
            requestedAt: boundary,
            status: PayoutStatus.failed,
            reference: 'TXN${10000 + _random.nextInt(90000)}',
            failureReason: 'The bank did not respond. We retried the next day.',
            isScheduled: true,
          ),
        );
      }
      payouts.add(
        Payout(
          id: _id('pay'),
          amountPaise: amount,
          requestedAt: failedOnce
              ? boundary.add(const Duration(days: 1))
              : boundary,
          status: PayoutStatus.paid,
          reference: 'TXN${10000 + _random.nextInt(90000)}',
          isScheduled: true,
        ),
      );
    }
    payouts.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return payouts;
  }

  List<AppNotification> _seedNotifications(
    List<Payout> payouts,
    PartnerProfile partner,
  ) {
    final latestPaid = payouts.firstWhere((p) => p.status == PayoutStatus.paid);
    final insurance = partner.documentFor(DocumentType.insurance);
    final lastDelivered = _history.firstWhere(
      (t) =>
          t.status == OrderStatus.delivered &&
          now.difference(t.lastUpdatedAt).inHours >= 20,
    );

    final notifications = [
      AppNotification(
        id: 'ntf-payout',
        category: NotificationCategory.earnings,
        title: 'Weekly payout sent',
        body:
            '${formatPaise(latestPaid.amountPaise)} has been transferred to your ${partner.bank!.bankName} account ending ${partner.bank!.last4}.',
        at: latestPaid.requestedAt,
        isRead: now.difference(latestPaid.requestedAt).inDays >= 2,
        deepLink: AppLink(AppLinkRoute.payout, latestPaid.id),
      ),
      AppNotification(
        id: 'ntf-peak',
        category: NotificationCategory.incentive,
        title: 'Dinner peak bonus is live 🎉',
        body: 'Earn ₹10 extra on every order delivered between 7 PM and 11 PM today.',
        at: now.subtract(const Duration(hours: 3)),
        deepLink: const AppLink(AppLinkRoute.incentive, 'inc-peak'),
      ),
      AppNotification(
        id: 'ntf-insurance',
        category: NotificationCategory.account,
        title: 'Insurance expiring soon',
        body:
            'Your vehicle insurance expires on ${formatDate(insurance.expiresOn!, now: now)}. Upload the renewed policy to keep receiving orders.',
        at: now.subtract(const Duration(hours: 6)),
        deepLink: const AppLink(AppLinkRoute.document, 'insurance'),
      ),
      AppNotification(
        id: 'ntf-rating',
        category: NotificationCategory.account,
        title: 'You got a 5 star rating',
        body:
            '${lastDelivered.customer.firstName} rated your delivery ${lastDelivered.displayId} with 5 stars.',
        at: lastDelivered.lastUpdatedAt.add(const Duration(minutes: 30)),
        isRead: true,
        deepLink: AppLink(AppLinkRoute.order, lastDelivered.orderId),
      ),
      AppNotification(
        id: 'ntf-docs',
        category: NotificationCategory.account,
        title: 'Documents verified',
        body:
            'Your documents have been verified. You can now start delivering.',
        at: partner.joinedOn.add(const Duration(days: 2)),
        isRead: true,
      ),
    ];
    notifications.sort((a, b) => b.at.compareTo(a.at));
    return notifications;
  }

  List<SupportTicket> _seedTickets(List<Payout> payouts) {
    final failed = payouts.firstWhere((p) => p.status == PayoutStatus.failed);
    final tipOrder = _history.firstWhere(
      (t) =>
          t.status == OrderStatus.delivered &&
          now.difference(t.lastUpdatedAt).inDays >= 3,
    );
    final opened = now.subtract(const Duration(days: 1));

    return [
      SupportTicket(
        id: 'TKT-301',
        category: 'Payout delay',
        source: TicketSource.help,
        status: TicketStatus.resolved,
        createdAt: failed.requestedAt.add(const Duration(hours: 2)),
        messages: [
          SupportMessage(
            id: 'msg-1',
            from: MessageAuthor.rider,
            text: 'My weekly payout has not reached my bank yet.',
            at: failed.requestedAt.add(const Duration(hours: 2)),
          ),
          SupportMessage(
            id: 'msg-2',
            from: MessageAuthor.agent,
            text: 'Sorry about that. The bank did not respond on Monday, so we retried today. The money has been sent.',
            at: failed.requestedAt.add(const Duration(days: 1, hours: 1)),
          ),
        ],
      ),
      SupportTicket(
        id: 'TKT-302',
        category: 'Tip missing',
        source: TicketSource.order,
        orderId: tipOrder.orderId,
        status: TicketStatus.awaitingYou,
        createdAt: tipOrder.lastUpdatedAt.add(const Duration(hours: 1)),
        messages: [
          SupportMessage(
            id: 'msg-3',
            from: MessageAuthor.rider,
            text:
                'The customer said they added a tip for ${tipOrder.displayId} but I do not see it.',
            at: tipOrder.lastUpdatedAt.add(const Duration(hours: 1)),
          ),
          SupportMessage(
            id: 'msg-4',
            from: MessageAuthor.agent,
            text: 'We are checking with the payments team. Can you share a screenshot of the customer message?',
            at: tipOrder.lastUpdatedAt.add(const Duration(hours: 5)),
          ),
        ],
      ),
      SupportTicket(
        id: 'TKT-303',
        category: 'App not showing orders',
        source: TicketSource.chat,
        status: TicketStatus.open,
        createdAt: opened,
        messages: [
          SupportMessage(
            id: 'msg-5',
            from: MessageAuthor.rider,
            text: 'I was online for 30 minutes near Saket and got no orders.',
            at: opened,
          ),
        ],
      ),
    ];
  }

  List<Incentive> _seedIncentives() {
    final today = startOfDay(now);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    int deliveredBetween(DateTime from, [DateTime? to]) => _history
        .where(
          (t) =>
              t.status == OrderStatus.delivered &&
              !t.lastUpdatedAt.isBefore(from) &&
              (to == null || t.lastUpdatedAt.isBefore(to)) &&
              !t.lastUpdatedAt.isAfter(now),
        )
        .length;
    int deliveredSince(DateTime from) => deliveredBetween(from);
    Incentive peak(String id, String title, int fromHour, int toHour) {
      final start = today.add(Duration(hours: fromHour));
      final end = today.add(Duration(hours: toHour));
      final incentive = Incentive(
        id: id,
        type: IncentiveType.peakHours,
        title: title,
        tiers: const [IncentiveTier(target: 1, rewardPaise: 1000)],
        windowStart: start,
        windowEnd: end,
        progress: deliveredBetween(start, end),
        terms:
            '₹10 extra for every order delivered between '
            '${formatTime(start)} and ${formatTime(end)}.',
      );
      return incentive.copyWith(status: incentive.statusAt(now));
    }

    return [
      Incentive(
        id: 'inc-daily',
        type: IncentiveType.dailyMilestone,
        title: 'Daily milestones',
        tiers: const [
          IncentiveTier(target: 8, rewardPaise: 8000),
          IncentiveTier(target: 14, rewardPaise: 18000),
          IncentiveTier(target: 20, rewardPaise: 30000),
        ],
        windowStart: today,
        windowEnd: today.add(const Duration(days: 1)),
        progress: deliveredSince(today),
        status: IncentiveStatus.active,
        terms: 'Only delivered orders count. Progress resets at midnight.',
      ),
      Incentive(
        id: 'inc-weekly',
        type: IncentiveType.weeklyTarget,
        title: 'Weekly target',
        tiers: const [IncentiveTier(target: 90, rewardPaise: 70000)],
        windowStart: monday,
        windowEnd: monday.add(const Duration(days: 7)),
        progress: deliveredSince(monday),
        status: IncentiveStatus.active,
        terms: 'Deliver 90 orders between Monday and Sunday.',
      ),
      peak('inc-lunch', 'Lunch peak bonus', 12, 15),
      peak('inc-peak', 'Dinner peak bonus', 19, 23),
    ];
  }
}
