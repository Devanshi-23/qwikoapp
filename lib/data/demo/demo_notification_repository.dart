import '../../core/domain_events.dart';
import '../../models/announcement.dart';
import '../../models/notification.dart';
import '../repositories/notification_repository.dart';
import 'demo_backend.dart';
import 'demo_engine.dart';

class DemoNotificationRepository implements NotificationRepository {
  DemoNotificationRepository(this._backend);

  final DemoBackend _backend;

  List<AppNotification> get _items => _backend.db.notifications;

  void _changed() => _backend.events.emit(const NotificationsChanged());

  @override
  Future<List<AppNotification>> fetchAll() => _backend.engine.run(
    OperationType.loadNotifications,
    () => List.unmodifiable(_items),
  );

  @override
  Future<void> markRead(String id) =>
      _backend.engine.run(OperationType.updateNotifications, () {
        final index = _items.indexWhere((n) => n.id == id);
        if (index == -1) return;
        _items[index] = _items[index].copyWith(isRead: true);
        _changed();
      });

  @override
  Future<void> markAllRead() =>
      _backend.engine.run(OperationType.updateNotifications, () {
        for (var i = 0; i < _items.length; i++) {
          _items[i] = _items[i].copyWith(isRead: true);
        }
        _changed();
      });

  @override
  Future<void> dismiss(String id) =>
      _backend.engine.run(OperationType.updateNotifications, () {
        _items.removeWhere((n) => n.id == id);
        _changed();
      });

  @override
  Future<void> restore(AppNotification notification) =>
      _backend.engine.run(OperationType.updateNotifications, () {
        if (_items.any((n) => n.id == notification.id)) return;
        _items
          ..add(notification)
          ..sort((a, b) => b.at.compareTo(a.at));
        _changed();
      });

  @override
  Future<List<Announcement>> announcements() => _backend.engine.run(
    OperationType.loadNotifications,
    () => List.unmodifiable(_backend.db.announcements),
  );

  @override
  Future<void> dismissAnnouncement(String id) =>
      _backend.engine.run(OperationType.updateNotifications, () {
        _backend.db.announcements.removeWhere((a) => a.id == id);
        _changed();
      });
}
