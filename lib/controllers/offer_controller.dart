import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../core/failures.dart';
import '../core/formatters.dart';
import '../data/repositories/offer_repository.dart';
import '../models/trip.dart';
import 'active_trip_controller.dart';
import 'availability_controller.dart';
import 'device_controller.dart';
import 'wallet_controller.dart';

/// How an offer left the screen.
enum OfferOutcome {
  accepted,
  declined,

  /// The countdown ran out.
  missed,

  /// The connection dropped while the offer was open; not counted as missed.
  released,

  /// Another partner took it and the rider dismissed the notice.
  withdrawn,
}

/// Shows one offer at a time and queues the rest. Listens for offers while
/// the rider is online (not on a break) and has no trip. Owns the countdown
/// so an offer times out on any screen.
class OfferController extends ChangeNotifier {
  OfferController({
    required this._repository,
    required this._availability,
    required this._trip,
    required this._wallet,
    required this._device,
    required this._clock,
  }) {
    for (final dependency in _dependencies) {
      dependency.addListener(_sync);
    }
  }

  /// Queued offers older than this are dropped without being shown.
  static const queuedOfferMaxAge = Duration(seconds: 60);
  static const tickInterval = Duration(seconds: 1);

  final OfferRepository _repository;
  final AvailabilityController _availability;
  final ActiveTripController _trip;
  final WalletController _wallet;
  final DeviceController _device;
  final Clock _clock;

  final StreamController<OfferOutcome> _outcomes =
      StreamController<OfferOutcome>.broadcast();
  StreamSubscription<OfferEvent>? _subscription;
  DeliveryOffer? _offer;
  final List<DeliveryOffer> _queue = [];
  bool _unavailable = false;
  bool _extended = false;
  Timer? _ticker;
  bool _busy = false;
  bool _enabled = false;
  bool _disposed = false;

  List<Listenable> get _dependencies => [_availability, _trip, _device];

  /// The offer on screen.
  DeliveryOffer? get offer => _offer;

  /// The offer on screen was taken by another partner.
  bool get isUnavailable => _unavailable;

  bool get isBusy => _busy;

  bool get isListening => _subscription != null;

  int get queuedCount => _queue.length;

  /// The offer's time was doubled for assistive technology.
  bool get hasExtraTime => _extended;

  Stream<OfferOutcome> get outcomes => _outcomes.stream;

  /// Time left to answer the offer on screen.
  Duration? get remaining {
    final expiresAt = _offer?.expiresAt;
    if (expiresAt == null) return null;
    final left = expiresAt.difference(_clock.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Why the offer on screen can't be accepted: its cash on delivery would
  /// take cash in hand over the limit (plan 3.8.6). Prepaid offers are
  /// always acceptable.
  String? get acceptBlockedReason {
    final offer = _offer;
    if (offer == null || !offer.isCod || !_wallet.isReady) return null;
    final cash = _wallet.cash;
    return cash.canCollect(offer.codAmountPaise)
        ? null
        : codLimitReason(cash.roomPaise);
  }

  /// Turned on after sign-in; off while signed out.
  set enabled(bool value) {
    _enabled = value;
    _sync();
  }

  bool get _canReceive =>
      _enabled && _availability.receivesOffers && !_trip.hasTrip;

  void _sync() {
    if (!_canReceive) {
      _clearAll();
    } else if (!_device.networkAvailable && _offer != null && !_unavailable) {
      _queue.clear();
      _finish(OfferOutcome.released);
    }
    if (_canReceive && _subscription == null) {
      _subscription = _repository
          .watchOffers(position: () => _availability.position)
          .listen(_onEvent);
    } else if (!_canReceive && _subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }
  }

  void _onEvent(OfferEvent event) {
    switch (event) {
      case OfferArrived(:final offer):
        if (_offer == null) {
          _show(offer);
        } else {
          _queue.add(offer);
          _notify();
        }
      case OfferWithdrawn(:final offerId):
        if (_offer?.id == offerId) {
          _unavailable = true;
          _stopTicker();
        } else {
          _queue.removeWhere((o) => o.id == offerId);
        }
        _notify();
    }
  }

  /// The countdown starts when the offer is shown (plan 3.8.7).
  void _show(DeliveryOffer offer) {
    _offer = offer.copyWith(shownAt: _clock.now());
    _unavailable = false;
    _extended = false;
    _stopTicker();
    _ticker = Timer.periodic(tickInterval, (_) => _onTick());
    _notify();
  }

  void _onTick() {
    if (_offer == null || _unavailable) return;
    if (remaining == Duration.zero && !_busy) {
      unawaited(miss());
      return;
    }
    _notify();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Clears the offer on screen and shows the next queued offer that is
  /// still fresh.
  void _finish(OfferOutcome outcome) {
    _offer = null;
    _unavailable = false;
    _extended = false;
    _stopTicker();
    _emit(outcome);
    final now = _clock.now();
    while (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (now.difference(next.createdAt) <= queuedOfferMaxAge) {
        _show(next);
        return;
      }
    }
    _notify();
  }

  void _clearAll() {
    if (_offer == null && _queue.isEmpty) return;
    _queue.clear();
    _offer = null;
    _unavailable = false;
    _extended = false;
    _stopTicker();
    _notify();
  }

  /// Doubles the time to answer, once per offer, for screen-reader and
  /// switch users.
  void extendTime() {
    final offer = _offer;
    if (offer == null || _extended) return;
    _extended = true;
    _offer = offer.copyWith(timeoutSeconds: offer.timeoutSeconds * 2);
    _notify();
  }

  DeliveryOffer _requireOffer() {
    final offer = _offer;
    if (offer == null) throw const OfferUnavailableFailure();
    return offer;
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_busy) throw const NotAllowedFailure('Please wait a moment.');
    _busy = true;
    _notify();
    try {
      return await action();
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<DeliveryTrip> accept() => _run(() async {
    final offer = _requireOffer();
    if (_unavailable) throw const OfferUnavailableFailure();
    final blocked = acceptBlockedReason;
    if (blocked != null) throw NotAllowedFailure(blocked);
    try {
      final trip = await _repository.accept(
        offer,
        position: _availability.position,
      );
      _queue.clear();
      _offer = null;
      _stopTicker();
      _notify();
      _emit(OfferOutcome.accepted);
      _trip.setTrip(trip);
      return trip;
    } on OfferUnavailableFailure {
      if (_offer?.id == offer.id) {
        _unavailable = true;
        _stopTicker();
      }
      rethrow;
    }
  });

  /// Declining is never blocked: the offer closes at once and the decision
  /// is recorded best-effort.
  Future<void> decline(DeclineReason reason, {String? note}) async {
    final offer = _requireOffer();
    if (_busy) throw const NotAllowedFailure('Please wait a moment.');
    _finish(OfferOutcome.declined);
    try {
      await _repository.decline(offer, reason, note: note);
    } on AppFailure {
      // The rider already moved on; a lost record only affects the log.
    }
  }

  /// The countdown ran out without a response.
  Future<void> miss() async {
    final offer = _offer;
    if (offer == null || _unavailable) return;
    _finish(OfferOutcome.missed);
    try {
      await _repository.markMissed(offer);
    } on AppFailure {
      // Missing an offer is recorded best-effort.
    }
  }

  /// Closes the "no longer available" notice.
  void dismissUnavailable() {
    if (_offer == null || !_unavailable) return;
    _finish(OfferOutcome.withdrawn);
  }

  void _emit(OfferOutcome outcome) {
    if (!_disposed) _outcomes.add(outcome);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final dependency in _dependencies) {
      dependency.removeListener(_sync);
    }
    _subscription?.cancel();
    _stopTicker();
    _outcomes.close();
    super.dispose();
  }
}
