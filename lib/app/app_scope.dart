import 'package:flutter/widgets.dart';

import 'app_services.dart';

/// Makes [AppServices] available to every screen. Screens listen to the
/// individual controllers they need with `ListenableBuilder`.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context.');
    return scope!.services;
  }

  /// For shared widgets that also render outside the app, such as in tests.
  static AppServices? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()?.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

extension AppScopeContext on BuildContext {
  AppServices get services => AppScope.of(this);
}
