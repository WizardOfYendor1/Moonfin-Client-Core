import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../ui/navigation/app_router.dart';

class LocalNotificationBootstrap {
  LocalNotificationBootstrap._();

  static final LocalNotificationBootstrap instance =
      LocalNotificationBootstrap._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open');

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        _navigate(response.payload);
      },
    );
    _initialized = true;
  }

  void _navigate(String? route) {
    if (route == null || route.trim().isEmpty) return;
    appRouter.go(route.trim());
  }

  Future<String?> getLaunchRoute() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final route = details?.notificationResponse?.payload?.trim();
    return (route != null && route.isNotEmpty) ? route : null;
  }
}
