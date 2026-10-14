import 'geo_point.dart';
import 'order.dart';
import 'trip.dart';

/// Problems a rider can report at the store, in the order they're offered.
const List<IssueType> storeIssueTypes = [
  IssueType.orderNotReady,
  IssueType.itemMissing,
  IssueType.itemDamaged,
  IssueType.storeClosed,
  IssueType.wrongOrder,
];

extension StoreIssueText on IssueType {
  String get storeLabel => switch (this) {
    IssueType.orderNotReady => 'Order not ready',
    IssueType.itemMissing => 'Item missing',
    IssueType.itemDamaged => 'Item damaged',
    IssueType.storeClosed => 'Store closed',
    IssueType.wrongOrder => 'Wrong order handed over',
    _ => 'Other issue',
  };

  String get storeHint => switch (this) {
    IssueType.orderNotReady => 'Keep waiting. Waiting pay starts after 5 min.',
    IssueType.itemMissing => 'The store replaces or removes the item.',
    IssueType.itemDamaged => 'The store replaces or removes the item.',
    IssueType.storeClosed =>
      'Cancel with compensation. You must be at the '
          'store.',
    IssueType.wrongOrder => 'The store fixes it, then you check again.',
    _ => '',
  };

  bool get needsItems =>
      this == IssueType.itemMissing || this == IssueType.itemDamaged;
}

/// What the store does about a missing or damaged item (plan 3.8.4).
enum ItemResolution {
  replace('Store replaces it'),
  remove('Remove from order');

  const ItemResolution(this.label);

  final String label;
}

class StoreIssueRequest {
  const StoreIssueRequest({
    required this.type,
    this.items = const [],
    this.resolution,
    this.note,
    this.position,
  });

  final IssueType type;

  /// Affected items, for missing or damaged items.
  final List<ItemRef> items;
  final ItemResolution? resolution;
  final String? note;

  /// Rider position; "Store closed" needs the rider at the store.
  final GeoPoint? position;
}

/// Where a store issue left the trip: still waiting, continuing, or
/// cancelled with compensation.
class StoreIssueResult {
  const StoreIssueResult({
    required this.trip,
    required this.outcome,
    required this.message,
  });

  final DeliveryTrip trip;
  final IssueOutcome outcome;
  final String message;
}
