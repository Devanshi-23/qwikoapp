import 'dart:async';

import '../../core/domain_events.dart';
import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/activity.dart';
import '../../models/app_link.dart';
import '../../models/geo_point.dart';
import '../../models/media_ref.dart';
import '../../models/money.dart';
import '../../models/notification.dart';
import '../../models/order.dart';
import '../../models/store_issue.dart';
import '../../models/trip.dart';
import '../repositories/demo_controls.dart';
import '../repositories/trip_repository.dart';
import 'demo_backend.dart';

class DemoTripRepository implements TripRepository {
  DemoTripRepository(this._backend);

  /// How long the store says it needs when an order isn't ready; a repeat
  /// report gets the longer delay.
  static const Duration firstStoreDelay = Duration(minutes: 6);
  static const Duration repeatStoreDelay = Duration(minutes: 10);

  /// The store fixes a wrong order in this time.
  static const Duration wrongOrderFix = Duration(seconds: 60);

  static const int maxChatLength = 200;
  static const Duration customerReplyDelay = Duration(seconds: 2);

  /// How far the pin moves when the customer shares their exact location.
  static const double sharedLocationOffsetM = 150;

  static const int maxOtpAttempts = 3;
  static const Duration otpLockout = Duration(seconds: 30);

  static const Duration tipDelay = Duration(seconds: 10);
  static const int tipPaise = 1000;

  final DemoBackend _backend;

  /// Wrong delivery OTPs per order, and when entry unlocks again.
  final Map<String, int> _wrongOtps = {};
  final Map<String, DateTime> _otpLockedUntil = {};

  bool get _offline => !_backend.engine.networkAvailable;

  @override
  Future<DeliveryTrip?> activeTrip() =>
      _backend.engine.run(OperationType.loadTrip, () => _backend.db.activeTrip);

  DeliveryTrip _requireTrip(String tripId) {
    final trip = _backend.db.activeTrip;
    if (trip == null || trip.id != tripId) {
      throw const NotFoundFailure('This trip is no longer active.');
    }
    if (trip.cancellation != null) {
      throw const NotAllowedFailure('This order was cancelled.');
    }
    return trip;
  }

  DeliveryTrip _requireAtStore(String tripId) {
    final trip = _requireTrip(tripId);
    if (trip.status != TripStatus.atStore) {
      throw const NotAllowedFailure('Mark that you have arrived at the store.');
    }
    return trip;
  }

  void _requireNearStore(DeliveryTrip trip, GeoPoint? position) => _requireNear(
    position,
    trip.store.location,
    DeliveryTrip.pickupGeofenceM,
    'the store',
  );

  void _requireNear(
    GeoPoint? position,
    GeoPoint target,
    int radiusM,
    String what,
  ) {
    if (position == null) {
      throw NotAllowedFailure(
        "We can't find your location. Turn on location to confirm you're at "
        '$what.',
      );
    }
    final distance = position.distanceMetersTo(target).round();
    if (distance > radiusM) {
      throw NotAllowedFailure(
        'You need to be within $radiusM m of $what. You are '
        '${formatDistance(distance)} away.',
      );
    }
  }

  DeliveryTrip _save(DeliveryTrip trip, {bool notify = true}) {
    _backend.db.activeTrip = trip;
    if (notify) _backend.events.emit(const TripChanged());
    return trip;
  }

  @override
  Future<DeliveryTrip> advance(
    String tripId,
    OrderStatus next, {
    GeoPoint? position,
  }) => _backend.engine.run(OperationType.updateTrip, () {
    final trip = _requireTrip(tripId);
    final now = _backend.clock.now();
    final queued = _offline;
    final current = trip.currentTask.status;

    final DeliveryTrip updated = switch ((current, next)) {
      (OrderStatus.headingToStore, OrderStatus.arrivedAtStore) => () {
        _requireNearStore(trip, position);
        return trip
            .updateAllTasks(
              (t) => t.transition(
                next,
                now,
                event: OrderEventType.arrivedAtStore,
                queued: queued,
              ),
            )
            .copyWith(status: TripStatus.atStore, waitStartedAt: now);
      }(),
      (OrderStatus.arrivedAtStore, OrderStatus.pickedUp) => () {
        final blocked = trip.pickupBlockedReason(now);
        if (blocked != null) throw NotAllowedFailure(blocked);
        return trip
            .copyWith(waitingPaise: trip.waitingPaiseAt(now))
            .updateAllTasks(
              (t) => t.transition(
                next,
                now,
                event: OrderEventType.pickedUp,
                queued: queued,
              ),
            )
            .updateCurrentTask(
              (t) => t.transition(OrderStatus.headingToCustomer, now),
            )
            .copyWith(status: TripStatus.inProgress);
      }(),
      (OrderStatus.headingToCustomer, OrderStatus.arrivedAtCustomer) => () {
        _requireNear(
          position,
          trip.currentTask.customer.location,
          DeliveryTask.customerGeofenceM,
          'the customer',
        );
        return trip.updateCurrentTask(
          (t) => t.transition(
            next,
            now,
            event: OrderEventType.arrivedAtCustomer,
            queued: queued,
          ),
        );
      }(),
      _ => throw NotAllowedFailure(
        "Can't move from ${current.name} to ${next.name}.",
      ),
    };

    return _save(updated);
  });

  /// Checklist changes stay on the device: no network, no latency.
  Future<DeliveryTrip> _local(
    String tripId,
    DeliveryTrip Function(DeliveryTrip trip) change,
  ) => Future.sync(() => _save(change(_requireAtStore(tripId)), notify: false));

  @override
  Future<DeliveryTrip> setItemChecked(
    String tripId,
    ItemRef item, {
    required bool checked,
  }) => _local(
    tripId,
    (trip) => trip.copyWith(
      tasks: [
        for (final task in trip.tasks)
          task.orderId != item.orderId
              ? task
              : task.copyWith(
                  items: [
                    for (var i = 0; i < task.items.length; i++)
                      i == item.index &&
                              task.items[i].status != ItemStatus.removed
                          ? task.items[i].copyWith(isPicked: checked)
                          : task.items[i],
                  ],
                ),
      ],
    ),
  );

  @override
  Future<DeliveryTrip> checkAllItems(String tripId) => _local(
    tripId,
    (trip) => trip
        .updateAllTasks(
          (task) => task.copyWith(
            items: [
              for (final item in task.items)
                item.status == ItemStatus.removed
                    ? item
                    : item.copyWith(isPicked: true),
            ],
          ),
        )
        .copyWith(checkedTags: trip.pickupChecks.toSet()),
  );

  @override
  Future<DeliveryTrip> setHandlingChecked(
    String tripId,
    OfferTag tag, {
    required bool checked,
  }) => _local(
    tripId,
    (trip) => trip.copyWith(
      checkedTags: checked
          ? {...trip.checkedTags, tag}
          : ({...trip.checkedTags}..remove(tag)),
    ),
  );

  @override
  Future<DeliveryTrip> setBag(
    String tripId, {
    required bool sealed,
    MediaRef? photo,
  }) => _local(
    tripId,
    (trip) => trip.copyWith(bagSealed: sealed, bagPhoto: photo),
  );

  @override
  Future<StoreIssueResult> reportStoreIssue(
    String tripId,
    StoreIssueRequest request,
  ) => _backend.engine.run(OperationType.updateTrip, () {
    final trip = _requireTrip(tripId);
    if (trip.isPickedUp) {
      throw const NotAllowedFailure(
        'Store issues can only be reported before pickup.',
      );
    }
    final now = _backend.clock.now();
    final resolved = switch (request.type) {
      IssueType.storeClosed => _storeClosed(trip, request),
      IssueType.orderNotReady => _notReady(_requireAtStore(tripId), now),
      IssueType.itemMissing || IssueType.itemDamaged => _itemIssue(
        _requireAtStore(tripId),
        request,
        now,
      ),
      IssueType.wrongOrder => _wrongOrder(_requireAtStore(tripId), now),
      _ => throw const NotAllowedFailure('Report this issue from Help.'),
    };

    final report = IssueReport(
      id: _backend.ids.next('iss'),
      type: request.type,
      at: now,
      affectedItems: resolved.affected,
      note: request.note,
      outcome: resolved.outcome,
    );
    var updated = resolved.trip.updateAllTasks(
      (t) => t
          .copyWith(issues: [...t.issues, report])
          .record(
            OrderEventType.issueReported,
            now,
            note: request.type.storeLabel,
            queued: _offline,
          ),
    );
    final cancelReason = resolved.cancelReason;
    updated = cancelReason == null
        ? _save(updated)
        : _backend.cancelTrip(
            updated,
            by: CancelledBy.store,
            reason: cancelReason,
            atStore: true,
          );
    return StoreIssueResult(
      trip: updated,
      outcome: resolved.outcome,
      message: resolved.message,
    );
  });

  _Resolved _storeClosed(DeliveryTrip trip, StoreIssueRequest request) {
    _requireNearStore(trip, request.position);
    return (
      trip: trip,
      outcome: IssueOutcome.cancelled,
      message: 'Order cancelled because the store is closed.',
      cancelReason: 'The store is closed.',
      affected: const [],
    );
  }

  _Resolved _notReady(DeliveryTrip trip, DateTime now) {
    final delay = trip.orderReadyAt == null
        ? firstStoreDelay
        : repeatStoreDelay;
    return (
      trip: trip.copyWith(orderReadyAt: now.add(delay)),
      outcome: IssueOutcome.waiting,
      message:
          'The store needs about ${delay.inMinutes} min more. Waiting pay '
          'starts after ${DeliveryTrip.freeWait.inMinutes} min at the store.',
      cancelReason: null,
      affected: const [],
    );
  }

  _Resolved _wrongOrder(DeliveryTrip trip, DateTime now) => (
    trip: trip
        .updateAllTasks(
          (task) => task.copyWith(
            items: [
              for (final item in task.items) item.copyWith(isPicked: false),
            ],
          ),
        )
        .copyWith(
          checkedTags: const {},
          storeFixingUntil: now.add(wrongOrderFix),
        ),
    outcome: IssueOutcome.waiting,
    message:
        'The store is fixing the order (about 1 min). Check every item '
        'again when they hand it over.',
    cancelReason: null,
    affected: const [],
  );

  _Resolved _itemIssue(
    DeliveryTrip trip,
    StoreIssueRequest request,
    DateTime now,
  ) {
    if (request.items.isEmpty) {
      throw const ValidationFailure('Choose the items with a problem.');
    }
    final resolution =
        request.resolution ??
        (throw const ValidationFailure('Choose what the store will do.'));
    final remove = resolution == ItemResolution.remove;
    final affected = <String>[];
    final valueBefore = _orderValue(trip.tasks);

    final tasks = [
      for (final task in trip.tasks)
        () {
          final picked = {
            for (final ref in request.items)
              if (ref.orderId == task.orderId) ref.index,
          };
          if (picked.isEmpty) return task;
          final items = [
            for (var i = 0; i < task.items.length; i++)
              if (!picked.contains(i) ||
                  task.items[i].status == ItemStatus.removed)
                task.items[i]
              else ...[
                task.items[i].copyWith(
                  isPicked: false,
                  status: remove ? ItemStatus.removed : ItemStatus.replaced,
                ),
              ],
          ];
          for (final i in picked) {
            if (i < task.items.length) affected.add(task.items[i].label);
          }
          final changed = task.copyWith(items: items);
          return remove
              ? changed.copyWith(payment: changed.recomputedPayment)
              : changed;
        }(),
    ];
    if (affected.isEmpty) {
      throw const ValidationFailure('Choose the items with a problem.');
    }
    final count =
        '${affected.length} ${affected.length == 1 ? 'item' : 'items'}';

    if (!remove) {
      return (
        trip: trip.copyWith(tasks: tasks),
        outcome: IssueOutcome.replaced,
        message:
            'The store will replace $count. Check them again when they '
            'hand them over.',
        cancelReason: null,
        affected: affected,
      );
    }

    bool isEmpty(DeliveryTask task) =>
        task.items.every((item) => item.status == ItemStatus.removed);
    if (tasks.every(isEmpty)) {
      return (
        trip: trip.copyWith(tasks: tasks),
        outcome: IssueOutcome.cancelled,
        message: 'None of the items are available, so the order is cancelled.',
        cancelReason: 'None of the items are available.',
        affected: affected,
      );
    }

    final emptied = tasks.where(isEmpty).toList();
    final remaining = tasks.where((t) => !isEmpty(t)).toList();
    for (final task in emptied) {
      _closeTask(
        task.transition(
          OrderStatus.cancelled,
          now,
          event: OrderEventType.cancelled,
          note: 'None of the items are available.',
        ),
        payout: const PayoutBreakdown(),
      );
    }
    final less = valueBefore - _orderValue(tasks);
    final dropped = emptied.isEmpty
        ? ''
        : ' ${emptied.map((t) => t.displayId).join(', ')} was cancelled '
              'because none of its items are available.';
    return (
      trip: trip.copyWith(tasks: remaining, currentTaskIndex: 0),
      outcome: IssueOutcome.removed,
      message:
          'Removed $count. The customer pays ${formatPaise(less)} less; '
          'your pay is unchanged.$dropped',
      cancelReason: null,
      affected: affected,
    );
  }

  int _orderValue(List<DeliveryTask> tasks) =>
      tasks.fold(0, (sum, t) => sum + t.payment.orderValuePaise);

  @override
  Future<DeliveryTrip> cancelAfterLongWait(String tripId) =>
      _backend.engine.run(OperationType.updateTrip, () {
        final trip = _requireAtStore(tripId);
        final now = _backend.clock.now();
        if (!trip.canCancelForWaitAt(now)) {
          throw NotAllowedFailure(
            'You can cancel after waiting '
            '${DeliveryTrip.longWait.inMinutes} min for an order that '
            "isn't ready.",
          );
        }
        return _backend.cancelTrip(
          trip,
          by: CancelledBy.store,
          reason:
              'The order was not ready after '
              '${DeliveryTrip.longWait.inMinutes} min.',
          atStore: true,
        );
      });

  @override
  Future<TripCancellation> closeCancelledTrip(String tripId) =>
      _backend.engine.run(OperationType.updateTrip, () {
        final trip = _backend.db.activeTrip;
        if (trip == null || trip.id != tripId) {
          throw const NotFoundFailure('This trip is no longer active.');
        }
        final cancellation = trip.cancellation;
        if (cancellation == null) {
          throw const NotAllowedFailure('This trip is still active.');
        }
        final at = _backend.clock.now();
        for (var i = 0; i < trip.tasks.length; i++) {
          _closeTask(
            trip.tasks[i].transition(
              OrderStatus.cancelled,
              at,
              event: OrderEventType.cancelled,
              note: cancellation.reason,
            ),
            payout: i == 0
                ? PayoutBreakdown(
                    compensationPaise: cancellation.compensationPaise,
                    waitingPaise: cancellation.waitingPaise,
                  )
                : const PayoutBreakdown(),
          );
        }
        _backend.db.activeTrip = null;
        _backend.events
          ..emit(const LedgerChanged())
          ..emit(const TripChanged());
        return cancellation;
      });

  void _closeTask(DeliveryTask task, {required PayoutBreakdown payout}) =>
      _backend.closeTask(task, payout: payout);

  DeliveryTrip _requireCurrentStatus(String tripId, OrderStatus status) {
    final trip = _requireTrip(tripId);
    if (trip.currentTask.status != status) {
      throw NotAllowedFailure(switch (status) {
        OrderStatus.arrivedAtCustomer => "Tap \"I've arrived\" first.",
        OrderStatus.returningToStore => 'There is nothing to return.',
        _ => 'Not available at this step.',
      });
    }
    return trip;
  }

  bool _onDeliveryLeg(DeliveryTrip trip) {
    final status = trip.currentTask.status;
    return status == OrderStatus.headingToCustomer ||
        status == OrderStatus.arrivedAtCustomer;
  }

  @override
  Future<({bool answered, Duration duration})> callCustomer(String tripId) =>
      _backend.engine.run(OperationType.updateTrip, () {
        final trip = _requireTrip(tripId);
        if (!_onDeliveryLeg(trip)) {
          throw const NotAllowedFailure('You can call after pickup.');
        }
        final now = _backend.clock.now();
        final answered = _backend.customerResponse != CustomerResponse.noAnswer;
        final duration = answered ? const Duration(seconds: 42) : Duration.zero;
        _save(
          trip.updateCurrentTask(
            (t) => t
                .copyWith(contactAttempts: t.contactAttempts + 1)
                .record(
                  OrderEventType.callAttempted,
                  now,
                  note: answered ? 'Answered · 0:42' : 'No answer',
                  queued: _offline,
                ),
          ),
        );
        return (answered: answered, duration: duration);
      });

  static const List<String> _customerReplies = [
    'Okay, thank you!',
    'Sure, I am waiting.',
    'Coming down now.',
  ];

  @override
  Future<DeliveryTrip> sendChat(String tripId, String text) =>
      _backend.engine.run(OperationType.updateTrip, () {
        final message = text.trim();
        if (message.isEmpty) {
          throw const ValidationFailure('Type a message first.');
        }
        if (message.length > maxChatLength) {
          throw const ValidationFailure(
            'Messages can be up to $maxChatLength characters.',
          );
        }
        final trip = _requireTrip(tripId);
        if (!_onDeliveryLeg(trip)) {
          throw const NotAllowedFailure('Chat opens after pickup.');
        }
        final orderId = trip.currentTask.orderId;
        final updated = _save(
          trip.updateCurrentTask(
            (t) => t.record(
              OrderEventType.chatSent,
              _backend.clock.now(),
              note: message,
              queued: _offline,
            ),
          ),
        );
        if (_backend.customerResponse != CustomerResponse.noAnswer) {
          Timer(customerReplyDelay, () => _reply(tripId, orderId, message));
        }
        return updated;
      });

  void _reply(String tripId, String orderId, String to) {
    final trip = _backend.db.activeTrip;
    if (trip == null ||
        trip.id != tripId ||
        _offline ||
        _backend.events.isClosed) {
      return;
    }
    final index = trip.tasks.indexWhere((t) => t.orderId == orderId);
    if (index < 0) return;
    final sent = trip.tasks[index].chat.where(
      (e) => e.type == OrderEventType.chatSent,
    );
    final text = to.toLowerCase().contains('location')
        ? 'Sharing my location now.'
        : _customerReplies[(sent.length - 1) % _customerReplies.length];
    final tasks = [...trip.tasks];
    tasks[index] = tasks[index].record(
      OrderEventType.chatReceived,
      _backend.clock.now(),
      note: text,
    );
    _save(trip.copyWith(tasks: tasks));
  }

  @override
  Future<DeliveryTrip> requestCustomerLocation(String tripId) =>
      _backend.engine.run(OperationType.updateTrip, () {
        final trip = _requireTrip(tripId);
        if (!_onDeliveryLeg(trip)) {
          throw const NotAllowedFailure('Available after pickup.');
        }
        if (_backend.customerResponse == CustomerResponse.noAnswer) {
          throw const NotAllowedFailure(
            "The customer hasn't shared a location. Keep calling, or contact "
            'support.',
          );
        }
        final now = _backend.clock.now();
        final task = trip.currentTask;
        final moved = task.customer.copyWith(
          location: task.customer.location.moved(45, sharedLocationOffsetM),
        );
        return _save(
          trip.updateCurrentTask(
            (t) => t
                .copyWith(customer: moved)
                .transition(
                  OrderStatus.headingToCustomer,
                  now,
                  event: OrderEventType.locationShared,
                  note: 'The customer shared their exact location.',
                  queued: _offline,
                ),
          ),
        );
      });

  @override
  Future<String> contactSupportAboutAddress(String tripId) =>
      _backend.engine.run(OperationType.updateTrip, () {
        final trip = _requireTrip(tripId);
        if (!_onDeliveryLeg(trip)) {
          throw const NotAllowedFailure('Available after pickup.');
        }
        final now = _backend.clock.now();
        final ticket = _backend.ids.reference('TKT');
        final report = IssueReport(
          id: _backend.ids.next('iss'),
          type: IssueType.addressNotFound,
          at: now,
          outcome: IssueOutcome.escalated,
          ticketId: ticket,
        );
        _save(
          trip.updateCurrentTask(
            (t) => t
                .copyWith(issues: [...t.issues, report])
                .record(
                  OrderEventType.issueReported,
                  now,
                  note: "Can't find address",
                  queued: _offline,
                ),
          ),
        );
        return ticket;
      });

  @override
  Future<DeliveryTrip?> markUndeliverable(
    String tripId, {
    required String reason,
    bool refused = false,
  }) => _backend.engine.run(OperationType.updateTrip, () {
    final trip = _requireCurrentStatus(tripId, OrderStatus.arrivedAtCustomer);
    final now = _backend.clock.now();
    final task = trip.currentTask;
    if (!refused) {
      final blocked = task.undeliverableBlockedReason(now);
      if (blocked != null) throw NotAllowedFailure(blocked);
    }
    final report = IssueReport(
      id: _backend.ids.next('iss'),
      type: refused ? IssueType.customerRefused : IssueType.customerUnreachable,
      at: now,
      note: reason,
      outcome: IssueOutcome.cancelled,
    );
    final reported = trip.updateCurrentTask(
      (t) => t.copyWith(issues: [...t.issues, report]),
    );
    final updated = _backend.failDrop(
      reported,
      trip.currentTaskIndex,
      reason: reason,
      queued: _offline,
    );
    _backend.db.activeTrip = updated;
    _backend.events.emit(const TripChanged());
    return updated;
  });

  @override
  Future<({List<DeliveryTask> returned, DeliveryTrip? trip})> returnedToStore(
    String tripId, {
    GeoPoint? position,
  }) => _backend.engine.run(OperationType.updateTrip, () {
    final trip = _requireCurrentStatus(tripId, OrderStatus.returningToStore);
    _requireNearStore(trip, position);
    final now = _backend.clock.now();
    final returned = <DeliveryTask>[];
    final tasks = [
      for (final (i, task) in trip.tasks.indexed)
        if (task.status != OrderStatus.returningToStore)
          task
        else
          () {
            final done = task
                .transition(
                  OrderStatus.returned,
                  now,
                  event: OrderEventType.returned,
                  queued: _offline,
                )
                .copyWith(
                  payout: task.failedPayout(
                    returned: true,
                    waitingPaise: i == 0 ? trip.waitingPaise : 0,
                  ),
                );
            _backend.closeTask(done);
            returned.add(done);
            return done;
          }(),
    ];
    final next = _backend.nextLeg(
      trip.copyWith(tasks: tasks, notice: null),
      now,
    );
    _backend.db.activeTrip = next;
    _backend.events
      ..emit(const LedgerChanged())
      ..emit(const TripChanged());
    return (returned: returned, trip: next);
  });

  @override
  Future<DeliveryTrip?> dismissNotice(String tripId) => Future.sync(() {
    final trip = _backend.db.activeTrip;
    if (trip == null || trip.id != tripId) return null;
    if (trip.status == TripStatus.completed) {
      _backend.db.activeTrip = null;
      _backend.events.emit(const TripChanged());
      return null;
    }
    return _save(trip.copyWith(notice: null), notify: false);
  });

  @override
  Future<OtpCheck> verifyDeliveryOtp(
    String tripId,
    String code,
  ) => _backend.engine.run(OperationType.updateTrip, () {
    final trip = _requireCurrentStatus(tripId, OrderStatus.arrivedAtCustomer);
    final task = trip.currentTask;
    final now = _backend.clock.now();
    final lockedUntil = _otpLockedUntil[task.orderId];
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      throw NotAllowedFailure(
        'Too many wrong codes. Try again in '
        '${formatClock(lockedUntil.difference(now))}.',
      );
    }
    if (code == task.deliveryOtp) {
      _wrongOtps.remove(task.orderId);
      _otpLockedUntil.remove(task.orderId);
      _save(
        trip.updateCurrentTask(
          (t) => t.record(
            OrderEventType.proofCaptured,
            now,
            note: 'OTP verified',
            queued: _offline,
          ),
        ),
      );
      return (verified: true, attemptsLeft: maxOtpAttempts, lockedUntil: null);
    }
    final wrong = (_wrongOtps[task.orderId] ?? 0) + 1;
    if (wrong >= maxOtpAttempts) {
      _wrongOtps.remove(task.orderId);
      final until = now.add(otpLockout);
      _otpLockedUntil[task.orderId] = until;
      return (verified: false, attemptsLeft: 0, lockedUntil: until);
    }
    _wrongOtps[task.orderId] = wrong;
    return (
      verified: false,
      attemptsLeft: maxOtpAttempts - wrong,
      lockedUntil: null,
    );
  });

  @override
  Future<bool> collectUpi(String tripId, int amountPaise) =>
      _backend.engine.run(OperationType.collectUpi, () {
        final trip = _requireCurrentStatus(
          tripId,
          OrderStatus.arrivedAtCustomer,
        );
        final due = trip.currentTask.payment.amountToCollectPaise;
        if (amountPaise <= 0 || amountPaise > due) {
          throw ValidationFailure('Enter an amount up to ${formatPaise(due)}.');
        }
        if (_backend.upiPaymentFails) return false;
        _save(
          trip.updateCurrentTask(
            (t) => t.record(
              OrderEventType.paymentCollected,
              _backend.clock.now(),
              note: 'UPI ${formatPaise(amountPaise)}',
            ),
          ),
        );
        return true;
      });

  void _checkProof(DeliveryTask task, DeliveryProof proof) {
    final method = task.requiredProof;
    if (method != ProofMethod.photo && !proof.otpVerified) {
      throw const NotAllowedFailure('Verify the customer OTP first.');
    }
    if (method != ProofMethod.otp && proof.photo == null) {
      throw const NotAllowedFailure('Add a delivery photo first.');
    }
    final due = task.payment.amountToCollectPaise;
    final paid = proof.cashCollectedPaise + proof.upiCollectedPaise;
    if (paid < due) {
      throw NotAllowedFailure(
        'Collect ${formatPaise(due - paid)} more before completing.',
      );
    }
  }

  void _scheduleTip(DeliveryTask delivered) {
    if (!_backend.tipAfterDelivery) return;
    Timer(tipDelay, () {
      final db = _backend.db;
      if (_backend.events.isClosed) return;
      final index = db.history.indexWhere(
        (t) => t.orderId == delivered.orderId,
      );
      if (index < 0) return;
      final now = _backend.clock.now();
      final task = db.history[index];
      final tipped = task
          .record(OrderEventType.tipReceived, now, note: formatPaise(tipPaise))
          .copyWith(payout: task.payout.copyWith(tipPaise: tipPaise));
      db.history[index] = tipped;
      _credit(EarningType.tip, tipPaise, tipped);
      _backend.notify(
        NotificationCategory.earnings,
        '${task.customer.firstName} added a ${formatPaise(tipPaise)} tip',
        'For order ${task.displayId}. It is in your earnings.',
        link: AppLink(AppLinkRoute.order, task.orderId),
      );
      _backend.events.emit(const LedgerChanged());
    });
  }

  @override
  Future<({DeliveryTask delivered, DeliveryTrip? trip})> completeDelivery(
    String tripId,
    DeliveryProof proof,
  ) => _backend.engine.run(OperationType.completeDelivery, () {
    final db = _backend.db;
    final trip = _requireTrip(tripId);
    final task = trip.currentTask;
    if (task.status != OrderStatus.arrivedAtCustomer) {
      throw const NotAllowedFailure('Mark that you have arrived first.');
    }
    _checkProof(task, proof);
    final now = _backend.clock.now();
    final othersDelivered = trip.tasks
        .where((t) => t.orderId != task.orderId)
        .every((t) => t.status == OrderStatus.delivered);
    final earnsBatchBonus = trip.tasks.length > 1 && othersDelivered;

    final delivered = task
        .transition(
          OrderStatus.delivered,
          now,
          event: OrderEventType.delivered,
          queued: _offline,
        )
        .copyWith(
          proof: proof,
          payout: task.payout.copyWith(
            waitingPaise: trip.currentTaskIndex == 0 ? trip.waitingPaise : 0,
            batchBonusPaise: earnsBatchBonus ? task.payout.batchBonusPaise : 0,
          ),
        );

    _credit(EarningType.orderPay, delivered.payout.orderPayPaise, delivered);
    _credit(EarningType.surge, delivered.payout.surgePaise, delivered);
    _credit(EarningType.waitingPay, delivered.payout.waitingPaise, delivered);
    _credit(
      EarningType.batchBonus,
      delivered.payout.batchBonusPaise,
      delivered,
    );

    db.cash = db.cash.copyWith(
      movements: [
        ...db.cash.movements,
        if (proof.cashCollectedPaise > 0)
          CashMovement(
            type: CashMovementType.codCollected,
            amountPaise: proof.cashCollectedPaise,
            at: now,
            orderId: delivered.orderId,
          ),
        if (proof.changeGivenPaise > 0)
          CashMovement(
            type: CashMovementType.changeGiven,
            amountPaise: proof.changeGivenPaise,
            at: now,
            orderId: delivered.orderId,
          ),
      ],
    );

    db.history.insert(0, delivered);
    _scheduleTip(delivered);
    _advanceIncentives(delivered, now);
    _backend.recordActivity(ActivityType.delivered, delivered.displayId);

    final next = _backend.nextLeg(
      trip.updateCurrentTask((_) => delivered),
      now,
    );
    db.activeTrip = next;

    _backend.events
      ..emit(OrderCompleted(delivered.orderId))
      ..emit(const LedgerChanged())
      ..emit(const WalletChanged())
      ..emit(const TripChanged());
    return (delivered: delivered, trip: next);
  });

  void _credit(EarningType type, int amountPaise, DeliveryTask task) =>
      _backend.creditLedger(type, amountPaise, task);

  /// Delivery counts toward daily and weekly incentives; reaching a tier
  /// credits the difference to the ledger.
  void _advanceIncentives(DeliveryTask delivered, DateTime now) {
    final db = _backend.db;
    for (var i = 0; i < db.incentives.length; i++) {
      final incentive = db.incentives[i];
      final inWindow =
          !now.isBefore(incentive.windowStart) &&
          now.isBefore(incentive.windowEnd);
      if (!inWindow) continue;

      final progressed = incentive.copyWith(progress: incentive.progress + 1);
      db.incentives[i] = progressed.copyWith(status: progressed.statusAt(now));
      final reward = progressed.earnedPaise - incentive.earnedPaise;
      if (reward <= 0) continue;
      db.ledger.insert(
        0,
        EarningEntry(
          id: _backend.ids.next('led'),
          type: EarningType.incentive,
          amountPaise: reward,
          at: now,
          label: switch (incentive.type) {
            IncentiveType.dailyMilestone =>
              'Daily milestone · ${progressed.progress} orders',
            IncentiveType.weeklyTarget => '${incentive.title} achieved',
            _ => '${incentive.title} · ${delivered.displayId}',
          },
        ),
      );
      if (!incentive.isPerOrder) {
        _backend.notify(
          NotificationCategory.incentive,
          'You earned ${formatPaise(reward)}',
          '${incentive.title}: ${progressed.progress} orders delivered.',
          link: AppLink(AppLinkRoute.incentive, incentive.id),
        );
      }
    }
  }
}

typedef _Resolved = ({
  DeliveryTrip trip,
  IssueOutcome outcome,
  String message,
  String? cancelReason,
  List<String> affected,
});
