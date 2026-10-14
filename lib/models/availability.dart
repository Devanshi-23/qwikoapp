import 'app_link.dart';
import 'geo_point.dart';

enum AvailabilityStatus { offline, online, onBreak }

/// Ordered by priority: account problems first, device problems last.
enum OnlineBlockerType {
  accountSuspended,
  verificationPending,
  documentExpired,
  cashLimitReached,
  locationPermissionOff,
  locationServiceOff,
  networkOffline,
}

/// Something that stops the rider going online, with the action that fixes
/// it.
class OnlineBlocker {
  const OnlineBlocker({
    required this.type,
    required this.message,
    required this.fixLabel,
    this.fixLink,
  });

  final OnlineBlockerType type;
  final String message;
  final String fixLabel;
  final AppLink? fixLink;

  @override
  bool operator ==(Object other) =>
      other is OnlineBlocker && other.type == type && other.message == message;

  @override
  int get hashCode => Object.hash(type, message);

  @override
  String toString() => 'OnlineBlocker(${type.name})';
}

/// Break lengths offered from the availability menu.
const List<Duration> breakLengths = [
  Duration(minutes: 15),
  Duration(minutes: 30),
];

class AvailabilityState {
  const AvailabilityState({
    this.status = AvailabilityStatus.offline,
    this.onlineSince,
    this.breakEndsAt,
    this.zoneId,
    this.idlePosition,
  });

  final AvailabilityStatus status;
  final DateTime? onlineSince;
  final DateTime? breakEndsAt;
  final String? zoneId;

  /// Rider position while not on a trip (plan 3.8.7).
  final GeoPoint? idlePosition;

  /// Online or on a break: the shift is running.
  bool get isOnline => status != AvailabilityStatus.offline;

  bool get isOnBreak => status == AvailabilityStatus.onBreak;

  /// Offers are sent only while online and not on a break.
  bool get receivesOffers => status == AvailabilityStatus.online;

  AvailabilityState copyWith({
    AvailabilityStatus? status,
    DateTime? onlineSince,
    bool clearOnlineSince = false,
    DateTime? breakEndsAt,
    bool clearBreakEndsAt = false,
    String? zoneId,
    GeoPoint? idlePosition,
  }) => AvailabilityState(
    status: status ?? this.status,
    onlineSince: clearOnlineSince ? null : onlineSince ?? this.onlineSince,
    breakEndsAt: clearBreakEndsAt ? null : breakEndsAt ?? this.breakEndsAt,
    zoneId: zoneId ?? this.zoneId,
    idlePosition: idlePosition ?? this.idlePosition,
  );

  @override
  String toString() => 'AvailabilityState(${status.name}, since $onlineSince)';
}
