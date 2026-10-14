enum AppLinkRoute {
  order,
  trip,
  incentive,
  payout,
  document,
  ticket,
  safety,
  cashInHand,
  accountStatus,
}

/// In-app deep link used by notifications and blockers; resolved by the
/// router.
class AppLink {
  const AppLink(this.route, [this.id]);

  final AppLinkRoute route;
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is AppLink && other.route == route && other.id == id;

  @override
  int get hashCode => Object.hash(route, id);

  @override
  String toString() => 'AppLink(${route.name}${id == null ? '' : ':$id'})';
}
