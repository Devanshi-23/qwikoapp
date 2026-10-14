import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../controllers/active_trip_controller.dart';
import '../controllers/availability_controller.dart';
import '../controllers/demo_controller.dart';
import '../controllers/device_controller.dart';
import '../controllers/earnings_controller.dart';
import '../controllers/history_controller.dart';
import '../controllers/incentives_controller.dart';
import '../controllers/navigation_controller.dart';
import '../controllers/notifications_controller.dart';
import '../controllers/offer_controller.dart';
import '../controllers/profile_controller.dart';
import '../controllers/safety_controller.dart';
import '../controllers/session_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/support_controller.dart';
import '../controllers/wallet_controller.dart';
import '../controllers/zones_controller.dart';
import '../core/clock.dart';
import '../core/domain_events.dart';
import '../data/demo/demo_auth_repository.dart';
import '../data/demo/demo_availability_repository.dart';
import '../data/demo/demo_backend.dart';
import '../data/demo/demo_dashboard_repositories.dart';
import '../data/demo/demo_earnings_repository.dart';
import '../data/demo/demo_engine.dart';
import '../data/demo/demo_history_repository.dart';
import '../data/demo/demo_misc_repositories.dart';
import '../data/demo/demo_notification_repository.dart';
import '../data/demo/demo_offer_repository.dart';
import '../data/demo/demo_profile_repository.dart';
import '../data/demo/demo_route_planner.dart';
import '../data/demo/demo_seed.dart';
import '../data/demo/demo_support_repository.dart';
import '../data/demo/demo_trip_repository.dart';
import '../data/demo/demo_wallet_repository.dart';
import '../data/repositories/session_store.dart';
import '../services/location/location_source.dart';
import '../services/location/simulated_location_source.dart';
import '../services/maps/google_map_view.dart';
import '../services/maps/map_renderer.dart';
import '../services/maps/mock_map_view.dart';
import '../services/routing/route_planner.dart';

/// Every controller the app uses, built once at startup. Swapping the demo
/// repositories for real ones only changes the factory below.
class AppServices {
  AppServices._({
    required this.clock,
    required this.events,
    required this.session,
    required this.profile,
    required this.settings,
    required this.device,
    required this.availability,
    required this.offers,
    required this.trip,
    required this.history,
    required this.earnings,
    required this.wallet,
    required this.incentives,
    required this.zones,
    required this.notifications,
    required this.support,
    required this.safety,
    required this.mapRenderer,
    required this.routePlanner,
    required this.location,
    required this.navigation,
    required this.demo,
  });

  factory AppServices.demo({
    Clock? clock,
    Duration latency = const Duration(milliseconds: 300),
    Duration? jitter,
    int seed = DemoSeed.defaultSeed,
    Duration firstOfferDelay = const Duration(seconds: 3),
    Duration offerInterval = const Duration(seconds: 20),
    Duration offerTakenAfter = const Duration(seconds: 4),
    SessionStore? sessionStore,
  }) {
    final appClock = clock ?? DemoClock();
    final events = DomainEventBus();
    final backend = DemoBackend(
      clock: appClock,
      engine: DemoEngine(
        latency: latency,
        jitter:
            jitter ??
            (latency == Duration.zero
                ? Duration.zero
                : const Duration(milliseconds: 150)),
      ),
      events: events,
      seed: seed,
      firstOfferDelay: firstOfferDelay,
      offerInterval: offerInterval,
      offerTakenAfter: offerTakenAfter,
    );
    final homeZone = backend.db.zones.firstWhere(
      (z) => z.id == backend.db.partner.homeZoneId,
      orElse: () => backend.db.zones.first,
    );

    final profile = ProfileController(
      repository: DemoProfileRepository(backend),
      events: events,
    );
    late final NavigationController navigation;
    final trip = ActiveTripController(
      repository: DemoTripRepository(backend),
      events: events,
      clock: appClock,
      position: () => navigation.locationBlocked ? null : navigation.position,
    );
    final wallet = WalletController(
      repository: DemoWalletRepository(backend),
      clock: appClock,
      events: events,
    );
    final device = DeviceController(DemoDeviceRepository(backend));
    final availability = AvailabilityController(
      repository: DemoAvailabilityRepository(backend),
      activity: DemoActivityRepository(backend),
      trip: trip,
      profile: profile,
      wallet: wallet,
      device: device,
      clock: appClock,
      events: events,
      idlePosition: homeZone.center,
      zoneId: homeZone.id,
    );
    final offers = OfferController(
      repository: DemoOfferRepository(backend),
      availability: availability,
      trip: trip,
      wallet: wallet,
      device: device,
      clock: appClock,
    );
    final history = HistoryController(
      repository: DemoHistoryRepository(backend),
      clock: appClock,
      events: events,
    );
    final earnings = EarningsController(
      repository: DemoEarningsRepository(backend),
      clock: appClock,
      events: events,
    );
    final incentives = IncentivesController(
      repository: DemoIncentiveRepository(backend),
      clock: appClock,
      events: events,
    );
    final zones = ZonesController(
      repository: DemoZoneRepository(backend),
      events: events,
    );
    final notifications = NotificationsController(
      repository: DemoNotificationRepository(backend),
      events: events,
    );
    final supportRepository = DemoSupportRepository(backend);
    final support = SupportController(
      repository: supportRepository,
      events: events,
    );
    late final SafetyController safety;
    final location = SimulatedLocationSource(
      clock: appClock,
      start: homeZone.center,
    );
    final routePlanner = DemoRoutePlanner(engine: backend.engine);
    navigation = NavigationController(
      planner: routePlanner,
      location: location,
      trip: trip,
      device: device,
      clock: appClock,
      simulation: location,
    );
    safety = SafetyController(
      repository: DemoSafetyRepository(backend, supportRepository),
      position: () => navigation.position,
      events: events,
    );
    final session = SessionController(
      auth: DemoAuthRepository(backend),
      store: sessionStore ?? MemorySessionStore(),
      profile: profile,
      availability: availability,
      offers: offers,
      trip: trip,
      accountData: [
        history,
        earnings,
        wallet,
        incentives,
        zones,
        notifications,
        support,
        safety,
      ],
    );

    return AppServices._(
      clock: appClock,
      events: events,
      session: session,
      profile: profile,
      settings: SettingsController(
        repository: DemoSettingsRepository(backend),
        events: events,
      ),
      device: device,
      availability: availability,
      offers: offers,
      trip: trip,
      history: history,
      earnings: earnings,
      wallet: wallet,
      incentives: incentives,
      zones: zones,
      notifications: notifications,
      support: support,
      safety: safety,
      mapRenderer: _mapRenderer(),
      routePlanner: routePlanner,
      location: location,
      navigation: navigation,
      demo: DemoController(
        backend,
        simulation: location,
        navigation: navigation,
      ),
    );
  }

  static MapRenderer _mapRenderer() {
    if (AppConfig.useGoogleMaps) return const GoogleMapRenderer();
    if (AppConfig.wantsGoogleMaps) {
      debugPrint(
        'MAP_PROVIDER=google but MAPS_API_KEY is empty; using the demo map.',
      );
    } else if (AppConfig.mapProvider != 'mock') {
      debugPrint(
        'Unknown MAP_PROVIDER "${AppConfig.mapProvider}"; using the demo map.',
      );
    }
    return const MockMapRenderer();
  }

  final Clock clock;
  final DomainEventBus events;
  final SessionController session;
  final ProfileController profile;
  final SettingsController settings;
  final DeviceController device;
  final AvailabilityController availability;
  final OfferController offers;
  final ActiveTripController trip;
  final HistoryController history;
  final EarningsController earnings;
  final WalletController wallet;
  final IncentivesController incentives;
  final ZonesController zones;
  final NotificationsController notifications;
  final SupportController support;
  final SafetyController safety;
  final MapRenderer mapRenderer;
  final RoutePlanner routePlanner;
  final LocationSource location;
  final NavigationController navigation;

  /// Present only in demo builds.
  final DemoController? demo;

  void dispose() {
    session.dispose();
    navigation.dispose();
    location.dispose();
    offers.dispose();
    availability.dispose();
    device.dispose();
    trip.dispose();
    profile.dispose();
    settings.dispose();
    history.dispose();
    earnings.dispose();
    wallet.dispose();
    incentives.dispose();
    zones.dispose();
    notifications.dispose();
    support.dispose();
    safety.dispose();
    demo?.dispose();
    events.dispose();
  }
}
