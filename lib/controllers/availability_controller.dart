import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../core/domain_events.dart';
import '../core/failures.dart';
import '../core/formatters.dart';
import '../data/repositories/activity_repository.dart';
import '../data/repositories/availability_repository.dart';
import '../models/activity.dart';
import '../models/app_link.dart';
import '../models/availability.dart';
import '../models/geo_point.dart';
import '../models/money.dart';
import '../models/partner.dart';
import 'active_trip_controller.dart';
import 'device_controller.dart';
import 'profile_controller.dart';
import 'wallet_controller.dart';

/// Online, offline and break state; what blocks going online; online time
/// and acceptance rate from the activity log, so they survive restarts
/// (plan 3.8.9).
class AvailabilityController extends ChangeNotifier {
  AvailabilityController({
    required this._repository,
    required this._activity,
    required this._trip,
    required this._profile,
    required this._wallet,
    required this._device,
    required this._clock,
    required DomainEventBus events,
    required GeoPoint idlePosition,
    required String zoneId,
    this.tickInterval = const Duration(seconds: 30),
  }) : _homePosition = idlePosition,
       _homeZoneId = zoneId,
       _state = AvailabilityState(idlePosition: idlePosition, zoneId: zoneId) {
    _subscription = events.stream.listen(_onEvent);
    for (final dependency in _dependencies) {
      dependency.addListener(_onDependencyChanged);
    }
  }

  static const activeOrderReason =
      'Finish or hand over your current order first.';

  static const breakDuringOrderReason =
      "You can't take a break during an order.";

  /// Acceptance rate looks back this far.
  static const acceptanceWindow = Duration(days: 7);

  final AvailabilityRepository _repository;
  final ActivityRepository _activity;
  final ActiveTripController _trip;
  final ProfileController _profile;
  final WalletController _wallet;
  final DeviceController _device;
  final Clock _clock;
  final GeoPoint _homePosition;
  final String _homeZoneId;
  final Duration tickInterval;
  late final StreamSubscription<DomainEvent> _subscription;

  AvailabilityState _state;

  /// The last seven days of activity, oldest first.
  List<ActivityEvent> _events = const [];
  bool _busy = false;
  bool _disposed = false;
  String? _notice;
  Timer? _ticker;

  List<Listenable> get _dependencies => [_trip, _profile, _wallet, _device];

  AvailabilityState get state => _state;

  AvailabilityStatus get status => _state.status;

  bool get isOnline => _state.isOnline;

  bool get isOnBreak => _state.isOnBreak;

  bool get receivesOffers => _state.receivesOffers;

  bool get isBusy => _busy;

  /// Where offers are calculated from while the rider has no trip.
  GeoPoint get position => _state.idlePosition!;

  String get zoneId => _state.zoneId!;

  /// Why the rider was taken offline or a break ended, shown once.
  String? get notice => _notice;

  void clearNotice() => _notice = null;

  /// Time left on the current break.
  Duration? get breakRemaining {
    final endsAt = _state.breakEndsAt;
    if (endsAt == null) return null;
    final left = endsAt.difference(_clock.now());
    return left.isNegative ? Duration.zero : left;
  }

  List<OnlineBlocker> get blockers => onlineBlockers(
    profile: _profile.profile,
    cash: _wallet.cash,
    networkAvailable: _device.networkAvailable,
    locationGranted: _device.locationPermissionGranted,
    locationServiceOn: _device.locationServiceEnabled,
    now: _clock.now(),
  );

  /// Everything that stops the rider going online, most important first.
  static List<OnlineBlocker> onlineBlockers({
    required PartnerProfile? profile,
    required CashInHand cash,
    required bool networkAvailable,
    required bool locationGranted,
    required DateTime now,
    bool locationServiceOn = true,
  }) {
    final expired = profile?.expiredDocumentsAt(now) ?? const [];
    final rejected = profile?.rejectedDocuments ?? const [];
    return [
      if (profile?.verification == VerificationStatus.suspended)
        const OnlineBlocker(
          type: OnlineBlockerType.accountSuspended,
          message: 'Your account is on hold.',
          fixLabel: 'View details',
          fixLink: AppLink(AppLinkRoute.accountStatus),
        )
      else if (profile != null && !profile.isVerified)
        OnlineBlocker(
          type: OnlineBlockerType.verificationPending,
          message: rejected.isNotEmpty
              ? 'Your ${rejected.first.type.title} was rejected. Upload a '
                    'new one.'
              : 'Your documents are being verified. You can go online once '
                    'they are approved.',
          fixLabel: rejected.isNotEmpty ? 'Upload again' : 'View documents',
          fixLink: const AppLink(AppLinkRoute.document),
        ),
      for (final doc in expired)
        OnlineBlocker(
          type: OnlineBlockerType.documentExpired,
          message:
              'Your ${doc.type.title} expired'
              '${doc.expiresOn == null ? '' : ' on ${formatDate(doc.expiresOn!, now: now)}'}'
              '. Upload a new one.',
          fixLabel: 'Upload new',
          fixLink: AppLink(AppLinkRoute.document, doc.type.name),
        ),
      if (cash.balancePaise >= cash.limitPaise)
        OnlineBlocker(
          type: OnlineBlockerType.cashLimitReached,
          message:
              'You hold ${formatPaise(cash.balancePaise)} in cash, over the '
              '${formatPaise(cash.limitPaise)} limit. Deposit cash to go '
              'online.',
          fixLabel: 'Deposit cash',
          fixLink: const AppLink(AppLinkRoute.cashInHand),
        ),
      if (!locationGranted)
        const OnlineBlocker(
          type: OnlineBlockerType.locationPermissionOff,
          message:
              'Location access is off. Orders are matched to where you '
              'are.',
          fixLabel: 'Allow location',
        )
      else if (!locationServiceOn)
        const OnlineBlocker(
          type: OnlineBlockerType.locationServiceOff,
          message: 'Location is turned off on this phone.',
          fixLabel: 'Turn on location',
        ),
      if (!networkAvailable)
        const OnlineBlocker(
          type: OnlineBlockerType.networkOffline,
          message:
              "You're offline. Going online needs an internet "
              'connection.',
          fixLabel: 'Check connection',
        ),
    ];
  }

  /// Time online today, excluding breaks; resets at local midnight.
  Duration get onlineToday {
    final now = _clock.now();
    final dayStart = startOfDay(now);
    Duration overlap(DateTime from, DateTime to) {
      final start = from.isBefore(dayStart) ? dayStart : from;
      return to.isAfter(start) ? to.difference(start) : Duration.zero;
    }

    var total = Duration.zero;
    DateTime? since;
    for (final event in _events) {
      if (event.at.isAfter(now)) break;
      switch (event.type) {
        case ActivityType.wentOnline || ActivityType.breakEnded:
          since ??= event.at;
        case ActivityType.wentOffline || ActivityType.breakStarted:
          if (since != null) total += overlap(since, event.at);
          since = null;
        default:
          break;
      }
    }
    if (since != null && receivesOffers) total += overlap(since, now);
    return total;
  }

  /// Offer decisions over the last seven days.
  AcceptanceStats get acceptance {
    final from = _clock.now().subtract(acceptanceWindow);
    return AcceptanceStats.from(_events.where((e) => e.at.isAfter(from)));
  }

  /// The last seven days of activity, newest first.
  List<ActivityEvent> get recentEvents => _events.reversed.toList();

  Future<void> loadActivity() async {
    final today = startOfDay(_clock.now());
    try {
      _events = await _activity.events(
        from: today.subtract(const Duration(days: 6)),
        to: today.add(const Duration(days: 1)),
      );
      _notify();
    } on AppFailure {
      // Online time and acceptance are informational; keep the last values.
    }
  }

  Future<void> goOnline() async {
    if (isOnline || _busy) return;
    final blocker = blockers.firstOrNull;
    if (blocker != null) throw NotAllowedFailure(blocker.message);
    await _run(() => _repository.goOnline(zoneId: zoneId));
    _notice = null;
    _state = _state.copyWith(
      status: AvailabilityStatus.online,
      onlineSince: _clock.now(),
    );
    _startTicker();
    _notify();
  }

  Future<void> goOffline() async {
    if (!isOnline || _busy) return;
    if (_trip.hasTrip) throw const NotAllowedFailure(activeOrderReason);
    await _run(_repository.goOffline);
    _setOffline();
  }

  Future<void> toggle() => isOnline ? goOffline() : goOnline();

  Future<void> startBreak(Duration length) async {
    if (!receivesOffers || _busy) return;
    if (_trip.hasTrip) throw const NotAllowedFailure(breakDuringOrderReason);
    await _run(() => _repository.startBreak(length));
    _state = _state.copyWith(
      status: AvailabilityStatus.onBreak,
      breakEndsAt: _clock.now().add(length),
    );
    _startTicker();
    _notify();
  }

  Future<void> endBreak() async {
    if (!isOnBreak || _busy) return;
    await _run(_repository.endBreak);
    _resumeFromBreak();
  }

  /// Simulated travel to another zone while idle (plan 3.8.7).
  void moveToZone(String zoneId, GeoPoint center) {
    if (_trip.hasTrip) throw const NotAllowedFailure(activeOrderReason);
    _state = _state.copyWith(zoneId: zoneId, idlePosition: center);
    _notify();
  }

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    _notify();
    try {
      await action();
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _resumeFromBreak() {
    _state = _state.copyWith(
      status: AvailabilityStatus.online,
      clearBreakEndsAt: true,
    );
    _startTicker();
    _notify();
  }

  void _setOffline() {
    _state = _state.copyWith(
      status: AvailabilityStatus.offline,
      clearOnlineSince: true,
      clearBreakEndsAt: true,
    );
    _ticker?.cancel();
    _ticker = null;
    _notify();
  }

  /// Ticks every second during a break for the countdown.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      isOnBreak ? const Duration(seconds: 1) : tickInterval,
      (_) => _onTick(),
    );
  }

  void _onTick() {
    final left = breakRemaining;
    if (isOnBreak && left == Duration.zero && !_busy) {
      _notice = "Your break is over. You'll receive orders again.";
      _resumeFromBreak();
      _repository.endBreak().catchError((Object _) {});
      return;
    }
    _notify();
  }

  /// A blocker that appears while online (cash over the limit after a COD
  /// order, an expired document, location turned off) takes effect once
  /// no trip is in progress (plan 3.8.9). Losing the network does not: the
  /// rider stays online and the app retries.
  void _onDependencyChanged() {
    if (isOnline && !_busy && !_trip.hasTrip) {
      final blocking = blockers
          .where((b) => b.type != OnlineBlockerType.networkOffline)
          .firstOrNull;
      if (blocking != null) {
        _notice = "You're offline. ${blocking.message}";
        _setOffline();
        _repository.goOffline().catchError((Object _) {});
        return;
      }
    }
    _notify();
  }

  void _onEvent(DomainEvent event) {
    switch (event) {
      case ActivityChanged():
        loadActivity();
      case DataReset():
        reset();
        loadActivity();
      default:
        break;
    }
  }

  /// Local reset on sign-out; the session records going offline first.
  void reset() {
    _setOffline();
    _state = _state.copyWith(zoneId: _homeZoneId, idlePosition: _homePosition);
    _events = const [];
    _notice = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _subscription.cancel();
    for (final dependency in _dependencies) {
      dependency.removeListener(_onDependencyChanged);
    }
    super.dispose();
  }
}
