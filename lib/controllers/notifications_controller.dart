import '../core/domain_events.dart';
import '../data/repositories/notification_repository.dart';
import '../models/announcement.dart';
import '../models/notification.dart';
import 'loadable_controller.dart';

/// Notifications and home announcements. Changes show immediately and roll
/// back if saving fails.
class NotificationsController extends LoadableController {
  NotificationsController({required this._repository, super.events});

  final NotificationRepository _repository;

  List<AppNotification> _items = const [];
  List<Announcement> _announcements = const [];
  NotificationCategory? _filter;

  /// Newest first.
  List<AppNotification> get items => _items;

  /// Null shows every category.
  NotificationCategory? get filter => _filter;

  List<AppNotification> get visibleItems => _filter == null
      ? _items
      : [
          for (final n in _items)
            if (n.category == _filter) n,
        ];

  void setFilter(NotificationCategory? category) {
    if (category == _filter) return;
    _filter = category;
    notify();
  }

  int get unreadCount => _items.where((n) => !n.isRead).length;

  List<Announcement> get announcements => _announcements;

  @override
  Future<void> fetch() async {
    final results = await Future.wait<Object>([
      _repository.fetchAll(),
      _repository.announcements(),
    ]);
    _items = results[0] as List<AppNotification>;
    _announcements = results[1] as List<Announcement>;
  }

  @override
  void clearData() {
    _items = const [];
    _announcements = const [];
    _filter = null;
  }

  @override
  bool shouldRefresh(DomainEvent event) => event is NotificationsChanged;

  Future<void> _optimistic(
    List<AppNotification> updated,
    Future<void> Function() save,
  ) async {
    final previous = _items;
    _items = updated;
    notify();
    try {
      await save();
    } catch (_) {
      _items = previous;
      notify();
      rethrow;
    }
  }

  Future<void> markRead(String id) => _optimistic([
    for (final n in _items) n.id == id ? n.copyWith(isRead: true) : n,
  ], () => _repository.markRead(id));

  Future<void> markAllRead() => _optimistic([
    for (final n in _items) n.copyWith(isRead: true),
  ], _repository.markAllRead);

  Future<void> dismiss(String id) => _optimistic([
    for (final n in _items)
      if (n.id != id) n,
  ], () => _repository.dismiss(id));

  Future<void> restore(AppNotification notification) => _optimistic(
    [..._items, notification]..sort((a, b) => b.at.compareTo(a.at)),
    () => _repository.restore(notification),
  );

  Future<void> dismissAnnouncement(String id) async {
    final previous = _announcements;
    _announcements = [
      for (final a in _announcements)
        if (a.id != id) a,
    ];
    notify();
    try {
      await _repository.dismissAnnouncement(id);
    } catch (_) {
      _announcements = previous;
      notify();
      rethrow;
    }
  }
}
