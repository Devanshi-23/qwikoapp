import 'dart:async';

/// Facts published by repositories after data changes. Controllers listen and
/// refresh, so one delivery updates history, earnings, wallet and activity
/// together.
sealed class DomainEvent {
  const DomainEvent();
}

class OrderCompleted extends DomainEvent {
  const OrderCompleted(this.orderId);

  final String orderId;
}

class TripChanged extends DomainEvent {
  const TripChanged();
}

class LedgerChanged extends DomainEvent {
  const LedgerChanged();
}

class WalletChanged extends DomainEvent {
  const WalletChanged();
}

class IncentivesChanged extends DomainEvent {
  const IncentivesChanged();
}

class ProfileChanged extends DomainEvent {
  const ProfileChanged();
}

class NotificationsChanged extends DomainEvent {
  const NotificationsChanged();
}

class ActivityChanged extends DomainEvent {
  const ActivityChanged();
}

class SupportChanged extends DomainEvent {
  const SupportChanged();
}

class SafetyChanged extends DomainEvent {
  const SafetyChanged();
}

/// Network reachability or location permission changed.
class DeviceChanged extends DomainEvent {
  const DeviceChanged();
}

/// Zone demand changed (schedule boundary or a demo override).
class DemandChanged extends DomainEvent {
  const DemandChanged();
}

/// All demo data was rebuilt from the seed.
class DataReset extends DomainEvent {
  const DataReset();
}

class DomainEventBus {
  final StreamController<DomainEvent> _controller =
      StreamController<DomainEvent>.broadcast(sync: true);

  Stream<DomainEvent> get stream => _controller.stream;

  void emit(DomainEvent event) => _controller.add(event);

  /// Delayed demo work checks this so it does nothing once the services
  /// are disposed.
  bool get isClosed => _controller.isClosed;

  Future<void> dispose() => _controller.close();
}
