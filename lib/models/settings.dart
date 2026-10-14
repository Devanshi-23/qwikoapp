import 'notification.dart';

class AppSettings {
  const AppSettings({
    this.orderNotifications = true,
    this.soundAlerts = true,
    this.vibration = true,
    this.language = 'English',
    this.introSeen = false,
    this.mutedCategories = const {},
  });

  final bool orderNotifications;
  final bool soundAlerts;

  /// Vibrate when a new offer arrives.
  final bool vibration;
  final String language;

  /// Whether the demo intro was shown on this device.
  final bool introSeen;

  /// Inbox categories the rider turned off. Safety alerts can't be muted.
  final Set<NotificationCategory> mutedCategories;

  bool allows(NotificationCategory category) =>
      category == NotificationCategory.safety ||
      !mutedCategories.contains(category);

  AppSettings copyWith({
    bool? orderNotifications,
    bool? soundAlerts,
    bool? vibration,
    String? language,
    bool? introSeen,
    Set<NotificationCategory>? mutedCategories,
  }) => AppSettings(
    orderNotifications: orderNotifications ?? this.orderNotifications,
    soundAlerts: soundAlerts ?? this.soundAlerts,
    vibration: vibration ?? this.vibration,
    language: language ?? this.language,
    introSeen: introSeen ?? this.introSeen,
    mutedCategories: mutedCategories ?? this.mutedCategories,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.orderNotifications == orderNotifications &&
      other.soundAlerts == soundAlerts &&
      other.vibration == vibration &&
      other.language == language &&
      other.introSeen == introSeen &&
      other.mutedCategories.length == mutedCategories.length &&
      other.mutedCategories.containsAll(mutedCategories);

  @override
  int get hashCode => Object.hash(
    orderNotifications,
    soundAlerts,
    vibration,
    language,
    introSeen,
    Object.hashAllUnordered(mutedCategories),
  );
}
