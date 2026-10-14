import 'app_link.dart';

enum NotificationCategory {
  offer('Orders'),
  earnings('Money'),
  incentive('Incentives'),
  account('Account'),
  safety('Safety'),
  system('Updates');

  const NotificationCategory(this.label);

  final String label;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.at,
    this.isRead = false,
    this.deepLink,
  });

  final String id;
  final NotificationCategory category;
  final String title;
  final String body;
  final DateTime at;
  final bool isRead;
  final AppLink? deepLink;

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    category: category,
    title: title,
    body: body,
    at: at,
    isRead: isRead ?? this.isRead,
    deepLink: deepLink,
  );

  @override
  bool operator ==(Object other) =>
      other is AppNotification && other.id == id && other.isRead == isRead;

  @override
  int get hashCode => Object.hash(id, isRead);

  @override
  String toString() => 'AppNotification($id, $title, read: $isRead)';
}
