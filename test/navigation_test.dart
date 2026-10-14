import 'package:flutter_test/flutter_test.dart';
import 'package:qwiko_delivery_agent/app/app_services.dart';
import 'package:qwiko_delivery_agent/controllers/availability_controller.dart';
import 'package:qwiko_delivery_agent/controllers/demo_controller.dart';
import 'package:qwiko_delivery_agent/controllers/navigation_controller.dart';
import 'package:qwiko_delivery_agent/core/clock.dart';
import 'package:qwiko_delivery_agent/data/repositories/demo_controls.dart';
import 'package:qwiko_delivery_agent/models/availability.dart';
import 'package:qwiko_delivery_agent/models/order.dart';
import 'package:qwiko_delivery_agent/models/route.dart';
import 'package:qwiko_delivery_agent/models/trip.dart';
import 'package:qwiko_delivery_agent/services/location/simulated_location_source.dart';
import 'package:qwiko_delivery_agent/services/maps/map_view_model.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

Future<void> waitFor(bool Function() condition, {int tries = 100}) async {
  for (var i = 0; i < tries && !condition(); i++) {
    await settle();
  }
  expect(condition(), isTrue, reason: 'condition not met in time');
}

void main() {
  late FakeClock clock;
  late AppServices services;

  setUp(() {
    services = AppServices.demo(
      clock: clock = FakeClock(DateTime(2026, 10, 13, 14)),
      latency: Duration.zero,
      firstOfferDelay: const Duration(minutes: 30),
      offerInterval: const Duration(minutes: 30),
    );
  });

  tearDown(() => services.dispose());

  NavigationController nav() => services.navigation;
  DemoController demo() => services.demo!;
  SimulatedLocationSource location() =>
      services.location as SimulatedLocationSource;

  Future<DeliveryTrip> acceptOrder() async {
    await services.session.signInWithEmail(
      email: 'arjun@example.com',
      password: 'password123',
    );
    await services.wallet.load();
    await services.availability.goOnline();
    expect(
      demo().sendOffer(const OfferRequest(payment: PaymentMode.prepaid)),
      isTrue,
    );
    await waitFor(() => services.offers.offer != null);
    return services.offers.accept();
  }

  Future<void> ready() =>
      waitFor(() => nav().status == RouteStatus.ready && !nav().isPlanning);

  /// Moves the demo clock and lets the simulated rider catch up.
  void drive(Duration duration) {
    clock.advance(duration);
    location().advance();
  }

  test('accepting an order plans a road route to the store', () async {
    final trip = await acceptOrder();
    await ready();

    final leg = nav().leg!;
    expect(leg.toStore, isTrue);
    expect(leg.to, trip.store.location);
    expect(nav().position, trip.startPosition);
    expect(nav().route!.isFallback, isFalse);
    expect(nav().remainingM, nav().route!.distanceM);
    expect(nav().route!.steps.first.instruction, startsWith('Head '));
    expect(nav().nextStep!.maneuver, isNot(Maneuver.depart));
    expect(nav().distanceToNextStepM, nav().nextStep!.distanceFromStartM);
    expect(nav().summary, contains('Arrive by'));

    final model = nav().mapModel;
    expect(
      model.markers.map((m) => m.kind),
      containsAll([
        MapMarkerKind.rider,
        MapMarkerKind.store,
        MapMarkerKind.customer,
      ]),
    );
    expect(model.polylines.map((l) => l.style), contains(MapLineStyle.route));
    expect(model.semanticLabel, contains(trip.store.name));
  });

  test('the rider moves with the demo clock and the ETA drops', () async {
    await acceptOrder();
    await ready();
    final total = nav().remainingM!;
    final eta = nav().eta!;

    drive(const Duration(seconds: 30));

    expect(nav().travelledM, closeTo(150, 5));
    expect(nav().remainingM, closeTo(total - 150, 5));
    expect(nav().eta, lessThan(eta));
    expect(nav().arrivalTime, clock.now().add(nav().eta!));
    expect(
      nav().mapModel.polylines.map((l) => l.style),
      contains(MapLineStyle.travelled),
    );
  });

  test(
    'jumping to the store arrives; picking up plans to the customer',
    () async {
      final trip = await acceptOrder();
      await ready();

      demo().jumpToNextStop();
      expect(nav().arrived, isTrue);
      expect(nav().remainingM, 0);

      await services.trip.arrivedAtStore();
      expect(nav().arrived, isTrue);
      await services.trip.checkAllItems();
      await services.trip.pickedUp();
      await waitFor(() => nav().leg?.toStore == false);
      await ready();

      expect(nav().leg!.to, trip.tasks.first.customer.location);
      expect(nav().position, trip.store.location);
      expect(nav().arrived, isFalse);
    },
  );

  test(
    'GPS loss keeps the last known position and recovers after 20 s',
    () async {
      await acceptOrder();
      await ready();
      drive(const Duration(seconds: 10));
      final known = nav().position;

      demo().loseGps();
      expect(nav().gpsLost, isTrue);
      drive(const Duration(seconds: 10));
      expect(nav().position, known);
      expect(nav().mapModel.markers.first.label, 'You (last known)');

      drive(const Duration(seconds: 11));
      expect(nav().gpsLost, isFalse);
      expect(nav().position, isNot(known));
    },
  );

  test('a route deviation recalculates from the new position', () async {
    await acceptOrder();
    await ready();
    drive(const Duration(seconds: 20));
    final before = nav().position!;

    final recalculating = nav().simulateDeviation();
    expect(nav().status, RouteStatus.recalculating);
    expect(nav().summary, isNull);
    await recalculating;

    expect(nav().status, RouteStatus.ready);
    final start = nav().route!.points.first;
    expect(
      start.distanceMetersTo(before),
      closeTo(NavigationController.deviationM, 2),
    );
    expect(nav().travelledM, 0);
  });

  test(
    'a routing failure falls back to a straight line; retry recovers',
    () async {
      demo().failNext(OperationType.planRoute);
      await acceptOrder();
      await waitFor(() => nav().status == RouteStatus.unavailable);

      expect(nav().route!.isFallback, isTrue);
      expect(nav().route!.points, hasLength(2));
      expect(nav().error, isNotNull);
      expect(
        nav().mapModel.polylines.map((l) => l.style),
        contains(MapLineStyle.fallback),
      );

      await nav().retry();
      expect(nav().status, RouteStatus.ready);
      expect(nav().route!.isFallback, isFalse);
    },
  );

  test('routing works with no network', () async {
    await acceptOrder();
    await ready();
    demo().networkAvailable = false;

    await nav().retry();

    expect(nav().status, RouteStatus.ready);
    expect(nav().route!.isFallback, isFalse);
  });

  test('blocked location freezes the position until it is allowed', () async {
    await acceptOrder();
    await ready();
    demo().locationPermissionGranted = false;
    expect(nav().permissionDenied, isTrue);
    final frozen = nav().position;

    drive(const Duration(seconds: 20));
    expect(nav().position, frozen);

    demo().locationPermissionGranted = true;
    expect(nav().position, isNot(frozen));
    expect(nav().travelledM, closeTo(100, 5));
  });

  test(
    'location service off blocks going online and freezes position',
    () async {
      demo().locationServiceEnabled = false;
      final blockers = services.availability.blockers.map((b) => b.type);
      expect(blockers, contains(OnlineBlockerType.locationServiceOff));
      expect(
        AvailabilityController.onlineBlockers(
          profile: null,
          cash: services.wallet.cash,
          networkAvailable: true,
          locationGranted: false,
          locationServiceOn: false,
          now: clock.now(),
        ).map((b) => b.type),
        isNot(contains(OnlineBlockerType.locationServiceOff)),
        reason: 'permission is fixed first',
      );

      await services.device.enableLocationService();
      expect(services.device.locationServiceEnabled, isTrue);
      expect(
        services.availability.blockers.map((b) => b.type),
        isNot(contains(OnlineBlockerType.locationServiceOff)),
      );
    },
  );

  test('the trip ending clears the route', () async {
    await acceptOrder();
    await ready();
    demo().resetData();
    await waitFor(() => nav().leg == null);
    expect(nav().status, RouteStatus.idle);
    expect(nav().mapModel.isEmpty, isTrue);
    expect(nav().route, isNull);
  });
}
