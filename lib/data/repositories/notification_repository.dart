import '../../models/announcement.dart';
import '../../models/notification.dart';

abstract interface class NotificationRepository {
  /// Newest first.
  Future<List<AppNotification>> fetchAll();

  Future<void> markRead(String id);

  Future<void> markAllRead();

  Future<void> dismiss(String id);

  /// Puts back a dismissed notification (undo).
  Future<void> restore(AppNotification notification);

  /// Home dashboard cards the rider hasn't dismissed.
  Future<List<Announcement>> announcements();

  Future<void> dismissAnnouncement(String id);
}
