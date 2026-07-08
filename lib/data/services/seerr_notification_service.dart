import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../ui/navigation/app_router.dart';
import '../../ui/widgets/floating_notification.dart';
import '../../util/platform_detection.dart';
import 'local_notification_bootstrap.dart';

class SeerrNotificationService {
  static const _channelId = 'seerr_notifications';
  static const _channelName = 'Requests';
  static const _channelDesc = 'Seerr request and library notifications';

  Future<void> initialize() async {
    await LocalNotificationBootstrap.instance.initialize();
  }

  void show(String title, String body, String route) {
    if (route.trim().isEmpty) return;

    if (PlatformDetection.isMobile) {
      _showLocal(title, body, route.trim());
    } else {
      _showBanner(title, body, route.trim());
    }
  }

  Future<void> _showLocal(String title, String body, String route) async {
    try {
      await LocalNotificationBootstrap.instance.plugin.show(
        id: route.hashCode,
        title: title.isNotEmpty ? title : _channelName,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        payload: route,
      );
    } catch (_) {}
  }

  void _showBanner(String title, String body, String route) {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    FloatingNotification.show(
      context,
      title,
      body,
      () => appRouter.go(route),
    );
  }

  Future<void> handleColdStart() async {
    final route = await LocalNotificationBootstrap.instance.getLaunchRoute();
    if (route == null) return;
    appRouter.go(route);
  }
}
