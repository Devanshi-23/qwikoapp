import 'app_link.dart';

enum AnnouncementKind { weather, incentive, info }

/// A dismissible card on the home dashboard.
class Announcement {
  const Announcement({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.link,
    this.linkLabel,
  });

  final String id;
  final AnnouncementKind kind;
  final String title;
  final String body;
  final AppLink? link;
  final String? linkLabel;

  @override
  bool operator ==(Object other) => other is Announcement && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
