import '../../models/activity.dart';
import '../../models/announcement.dart';
import '../../models/money.dart';
import '../../models/notification.dart';
import '../../models/order.dart';
import '../../models/partner.dart';
import '../../models/settings.dart';
import '../../models/support.dart';
import '../../models/trip.dart';
import '../../models/zone.dart';
import 'demo_catalog.dart';

/// All demo state, held in memory. Rebuilt from the seed on reset.
class DemoDatabase {
  DemoDatabase({
    required this.partner,
    required this.zones,
    required this.stores,
    required this.customers,
    required this.catalog,
    required this.history,
    required this.ledger,
    required this.payouts,
    required this.cash,
    required this.notifications,
    required this.activity,
    required this.tickets,
    required this.faqs,
    required this.incentives,
    required this.announcements,
    required this.nextOrderNumber,
  });

  PartnerProfile partner;
  final List<DeliveryZone> zones;
  final List<StoreInfo> stores;
  final List<CustomerInfo> customers;
  final List<CatalogItem> catalog;

  /// Finished orders, newest first.
  final List<DeliveryTask> history;

  /// Earnings ledger, newest first.
  final List<EarningEntry> ledger;

  /// Newest first.
  final List<Payout> payouts;
  CashInHand cash;

  /// Newest first.
  final List<AppNotification> notifications;

  /// Oldest first.
  final List<ActivityEvent> activity;
  final List<SupportTicket> tickets;
  final List<FaqArticle> faqs;

  /// Newest first.
  final List<SafetyIncident> incidents = [];
  final List<Incentive> incentives;

  /// Not yet dismissed.
  final List<Announcement> announcements;

  DeliveryTrip? activeTrip;

  /// Offers another partner has taken (or will take before this rider can
  /// accept).
  final Set<String> takenOfferIds = {};
  AppSettings settings = const AppSettings();
  bool signedIn = false;
  int nextOrderNumber;

  /// Clears history and money for a brand-new partner.
  void startFresh(PartnerProfile newPartner) {
    partner = newPartner;
    history.clear();
    ledger.clear();
    payouts.clear();
    activity.clear();
    tickets.clear();
    incidents.clear();
    cash = CashInHand(limitPaise: cash.limitPaise);
    activeTrip = null;
  }
}
