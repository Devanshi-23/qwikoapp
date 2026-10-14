import '../../core/domain_events.dart';
import '../../models/money.dart';
import '../../models/zone.dart';
import '../repositories/device_repository.dart';
import '../repositories/incentive_repository.dart';
import '../repositories/zone_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

/// Network and location permission come from the Demo Controls toggles.
class DemoDeviceRepository implements DeviceRepository {
  DemoDeviceRepository(this._backend);

  final DemoBackend _backend;

  @override
  bool get networkAvailable => _backend.networkAvailable;

  @override
  bool get locationPermissionGranted => _backend.locationPermissionGranted;

  @override
  Stream<void> get changes =>
      _backend.events.stream.where((e) => e is DeviceChanged);

  @override
  bool get locationServiceEnabled => _backend.locationServiceEnabled;

  /// Demo: the rider always taps "Allow" on the simulated prompt.
  @override
  Future<bool> requestLocationPermission() async {
    _backend.locationPermissionGranted = true;
    return true;
  }

  @override
  Future<void> enableLocationService() async =>
      _backend.locationServiceEnabled = true;
}

class DemoZoneRepository implements ZoneRepository {
  DemoZoneRepository(this._backend);

  final DemoBackend _backend;

  @override
  Future<List<DeliveryZone>> zones() => _backend.engine.run(
    OperationType.loadZones,
    () => List.unmodifiable(_backend.zonesAt(_backend.clock.now())),
  );
}

class DemoIncentiveRepository implements IncentiveRepository {
  DemoIncentiveRepository(this._backend);

  final DemoBackend _backend;

  @override
  Future<List<Incentive>> incentives() =>
      _backend.engine.run(OperationType.loadIncentives, () {
        final now = _backend.clock.now();
        return List.unmodifiable([
          for (final incentive in _backend.db.incentives)
            incentive.copyWith(status: incentive.statusAt(now)),
        ]);
      });
}
