import '../data/repositories/settings_repository.dart';
import '../models/notification.dart';
import '../models/settings.dart';
import 'loadable_controller.dart';

class SettingsController extends LoadableController {
  SettingsController({required this._repository, super.events});

  final SettingsRepository _repository;

  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  @override
  Future<void> fetch() async => _settings = await _repository.load();

  @override
  void clearData() => _settings = const AppSettings();

  Future<void> update(AppSettings settings) async {
    final previous = _settings;
    _settings = settings;
    notify();
    try {
      await _repository.save(settings);
    } catch (_) {
      _settings = previous;
      notify();
      rethrow;
    }
  }

  Future<void> setOrderNotifications(bool value) =>
      update(_settings.copyWith(orderNotifications: value));

  Future<void> setSoundAlerts(bool value) =>
      update(_settings.copyWith(soundAlerts: value));

  Future<void> setVibration(bool value) =>
      update(_settings.copyWith(vibration: value));

  Future<void> setLanguage(String language) =>
      update(_settings.copyWith(language: language));

  Future<void> setCategoryEnabled(NotificationCategory category, bool on) {
    final muted = {..._settings.mutedCategories};
    on ? muted.remove(category) : muted.add(category);
    return update(_settings.copyWith(mutedCategories: muted));
  }
}
