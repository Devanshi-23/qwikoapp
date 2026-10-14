import '../../models/activity.dart';
import '../../models/settings.dart';
import '../repositories/activity_repository.dart';
import '../repositories/settings_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

class DemoActivityRepository implements ActivityRepository {
  DemoActivityRepository(this._backend);

  final DemoBackend _backend;

  @override
  Future<List<ActivityEvent>> events({
    required DateTime from,
    required DateTime to,
  }) => _backend.engine.run(
    OperationType.loadActivity,
    () => _backend.db.activity
        .where((e) => !e.at.isBefore(from) && e.at.isBefore(to))
        .toList(),
  );
}

class DemoSettingsRepository implements SettingsRepository {
  DemoSettingsRepository(this._backend);

  final DemoBackend _backend;

  @override
  Future<AppSettings> load() => _backend.engine.run(
    OperationType.loadSettings,
    () => _backend.db.settings,
  );

  @override
  Future<void> save(AppSettings settings) => _backend.engine.run(
    OperationType.saveSettings,
    () => _backend.db.settings = settings,
  );
}
