import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../models/activity.dart';
import '../../models/partner.dart';
import '../repositories/availability_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

class DemoAvailabilityRepository implements AvailabilityRepository {
  DemoAvailabilityRepository(this._backend);

  final DemoBackend _backend;

  /// The server's own check, independent of what the app shows.
  void _checkCanGoOnline() {
    final db = _backend.db;
    final partner = db.partner;
    if (partner.verification != VerificationStatus.verified) {
      throw const NotAllowedFailure(
        'Your account must be verified before you can go online.',
      );
    }
    final expired = partner.expiredDocumentsAt(_backend.clock.now());
    if (expired.isNotEmpty) {
      throw NotAllowedFailure(
        'Your ${expired.first.type.title} has expired. Upload a new one to '
        'go online.',
      );
    }
    final cash = db.cash;
    if (cash.balancePaise >= cash.limitPaise) {
      throw NotAllowedFailure(
        'Deposit cash to go online. You hold '
        '${formatPaise(cash.balancePaise)}; the limit is '
        '${formatPaise(cash.limitPaise)}.',
      );
    }
  }

  void _checkNoTrip(String message) {
    if (_backend.db.activeTrip != null) throw NotAllowedFailure(message);
  }

  @override
  Future<void> goOnline({required String zoneId}) =>
      _backend.engine.run(OperationType.setAvailability, () {
        _checkCanGoOnline();
        final zone = _backend.db.zones.where((z) => z.id == zoneId);
        _backend.recordActivity(
          ActivityType.wentOnline,
          zone.isEmpty ? '' : zone.first.name,
        );
      });

  @override
  Future<void> goOffline() =>
      _backend.engine.run(OperationType.setAvailability, () {
        _checkNoTrip('Finish or hand over your current order first.');
        _backend.recordActivity(ActivityType.wentOffline);
      });

  @override
  Future<void> startBreak(Duration length) =>
      _backend.engine.run(OperationType.setAvailability, () {
        _checkNoTrip("You can't take a break during an order.");
        _backend.recordActivity(
          ActivityType.breakStarted,
          '${length.inMinutes} min',
        );
      });

  @override
  Future<void> endBreak() => _backend.engine.run(
    OperationType.setAvailability,
    () => _backend.recordActivity(ActivityType.breakEnded),
  );
}
