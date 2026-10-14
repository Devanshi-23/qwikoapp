import 'package:flutter/material.dart';

import '../models/app_link.dart';
import 'app_routes.dart';
import 'app_services.dart';

/// Opens the screen an [AppLink] points at. Returns false when the link has
/// nowhere to go (for example an order link without an id).
bool openAppLink(NavigatorState navigator, AppServices services, AppLink link) {
  final id = link.id;
  switch (link.route) {
    case AppLinkRoute.order:
      if (id == null) return false;
      navigator.pushNamed(AppRoutes.orderDetails, arguments: id);
    case AppLinkRoute.trip:
      if (services.trip.trip != null) {
        navigator.pushNamed(AppRoutes.activeOrder);
      } else if (id != null) {
        navigator.pushNamed(AppRoutes.orderDetails, arguments: id);
      } else {
        return false;
      }
    case AppLinkRoute.incentive:
      navigator.pushNamed(AppRoutes.incentives, arguments: id);
    case AppLinkRoute.payout:
      navigator.pushNamed(AppRoutes.payouts, arguments: id);
    case AppLinkRoute.document:
      navigator.pushNamed(AppRoutes.documents);
    case AppLinkRoute.ticket:
      if (id == null) {
        navigator.pushNamed(AppRoutes.help);
      } else {
        navigator.pushNamed(AppRoutes.ticket, arguments: id);
      }
    case AppLinkRoute.safety:
      navigator.pushNamed(AppRoutes.safety);
    case AppLinkRoute.cashInHand:
      navigator.pushNamed(AppRoutes.cashInHand);
    case AppLinkRoute.accountStatus:
      final profile = services.profile.profile;
      if (profile == null) return false;
      AppRoutes.goToAccountHome(navigator, profile);
  }
  return true;
}
