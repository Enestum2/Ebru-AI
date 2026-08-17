import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/ebru_viewmodel.dart';
import 'views/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox(StorageService.boxName);

  final settings = SettingsService();
  await settings.init();

  final storage = StorageService();
  await storage.init();

  final notifications = NotificationService();
  await notifications.init();

  runApp(
    EbruWallpaperApp(
      settings: settings,
      storage: storage,
      notifications: notifications,
    ),
  );
}

class EbruWallpaperApp extends StatelessWidget {
  final SettingsService settings;
  final StorageService storage;
  final NotificationService notifications;

  const EbruWallpaperApp({
    super.key,
    required this.settings,
    required this.storage,
    required this.notifications,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EbruViewModel(
        settings: settings,
        storage: storage,
        notifications: notifications,
      ),
      child: MaterialApp(
        title: 'Ebru AI',
        debugShowCheckedModeBanner: false,
        theme: buildEbruTheme(),
        home: const AuthGate(),
      ),
    );
  }
}
