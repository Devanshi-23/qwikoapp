import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'app_scope.dart';
import 'app_services.dart';
import 'app_theme.dart';

class QwikoApp extends StatelessWidget {
  const QwikoApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'Qwiko',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        initialRoute: AppRoutes.splash,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        onUnknownRoute: AppRoutes.onUnknownRoute,
      ),
    );
  }
}
