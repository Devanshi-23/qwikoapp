import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'services/storage/prefs_session_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    QwikoApp(services: AppServices.demo(sessionStore: PrefsSessionStore())),
  );
}
